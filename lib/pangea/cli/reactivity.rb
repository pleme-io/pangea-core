# frozen_string_literal: true

require 'yaml'
require 'pathname'
require 'set'

module Pangea
  class CLI
    # Reactivity graph — models typed "ask" relationships between workspaces
    # in a constellation (e.g. pangea-architectures/workspaces/*).
    #
    # arch-synthesizer emits a `reactivity:` block into each generated
    # pangea.yml describing which upstream (layer, workspace, output) values
    # this workspace asks for. This module parses those declarations across
    # all sibling workspaces and exposes queries: upstream_of (workspaces this
    # one asks from), downstream_of (workspaces that ask from this one), and
    # `cascade_set` (the transitive closure in both directions — the set of
    # workspaces that MUST plan/apply together when the user acts on one).
    #
    # Topological ordering uses Kahn's algorithm; cycles raise
    # Reactivity::CycleError with the offending node set.
    module Reactivity
      CycleError = Class.new(StandardError)
      MissingWorkspaceError = Class.new(StandardError)

      # A single typed ask declared in a workspace's pangea.yml.
      Ask = Struct.new(:layer, :workspace, :output, :bind, keyword_init: true) do
        def self.from_h(h)
          new(
            layer: h.fetch('layer'),
            workspace: h.fetch('workspace'),
            output: h.fetch('output'),
            bind: h.fetch('bind'),
          )
        end
      end

      # Orthogonal actions the workspace runs at every cascade visit.
      # Restricted to the allowlist below to prevent conflict with the
      # primary cascade command (plan/apply/destroy/deploy).
      ALLOWED_ACTIONS = %w[synth output init].freeze
      CONFLICTING_ACTIONS = %w[plan apply destroy deploy].freeze

      InvalidActionError = Class.new(StandardError)

      # A workspace in the constellation — its directory, name, declared asks,
      # and any per-cascade-visit actions (pre/post).
      class Workspace
        attr_reader :name, :dir, :asks, :pre_actions, :post_actions

        def initialize(name:, dir:, asks: [], pre_actions: [], post_actions: [])
          @name = name
          @dir = dir
          @asks = asks.freeze
          @pre_actions = pre_actions.freeze
          @post_actions = post_actions.freeze
          freeze
        end

        # Load a workspace from its pangea.yml (returns nil if the dir has no
        # pangea.yml). Missing blocks are fine — empty arrays are used.
        #
        # Schema:
        #   reactivity:
        #     asks: [{layer, workspace, output, bind}]
        #   cascade:
        #     default_depth: N
        #     pre_actions:  [synth, output, init]
        #     post_actions: [synth, output, init]
        def self.load(dir)
          yml_path = File.join(dir, 'pangea.yml')
          return nil unless File.exist?(yml_path)

          config = YAML.safe_load(File.read(yml_path)) || {}
          name = config['workspace'] || File.basename(dir)
          asks = Array(config.dig('reactivity', 'asks')).map { |h| Ask.from_h(h) }
          pre = validate_actions(Array(config.dig('cascade', 'pre_actions')), dir: dir)
          post = validate_actions(Array(config.dig('cascade', 'post_actions')), dir: dir)
          new(name: name, dir: dir, asks: asks, pre_actions: pre, post_actions: post)
        rescue InvalidActionError
          raise
        rescue StandardError
          nil
        end

        # Sanity-check declared actions: allowlist only, no conflicts with
        # plan/apply/destroy/deploy. Raises InvalidActionError on violation
        # so the user gets a clear message at scan time.
        def self.validate_actions(list, dir:)
          list.map do |a|
            s = a.to_s.strip
            if CONFLICTING_ACTIONS.include?(s)
              raise InvalidActionError,
                "#{dir}/pangea.yml declares cascade action '#{s}' which " \
                "conflicts with the primary command. Use the CLI instead."
            end
            unless ALLOWED_ACTIONS.include?(s)
              raise InvalidActionError,
                "#{dir}/pangea.yml declares unknown cascade action '#{s}'. " \
                "Allowed: #{ALLOWED_ACTIONS.join(', ')}."
            end
            s
          end.freeze
        end

        # Names of workspaces this one asks from (its direct upstream).
        def upstream_names
          asks.map(&:workspace).uniq
        end

        def reactive?
          !asks.empty?
        end
      end

      # Full constellation graph computed from a workspaces root directory.
      class Graph
        attr_reader :workspaces

        def initialize(workspaces)
          @workspaces = workspaces.freeze  # Hash<String, Workspace>
          freeze
        end

        # Scan a workspaces root directory (parent of many workspace dirs) and
        # build a Graph. Returns an empty Graph if the root doesn't exist or
        # contains no pangea.yml siblings.
        def self.scan(workspaces_root)
          return new({}) unless Dir.exist?(workspaces_root)

          ws = {}
          Dir.entries(workspaces_root).sort.each do |entry|
            next if entry.start_with?('.')

            dir = File.join(workspaces_root, entry)
            next unless File.directory?(dir)

            workspace = Workspace.load(dir)
            ws[workspace.name] = workspace if workspace
          end
          new(ws)
        end

        # Given a template file path, locate the enclosing workspaces root
        # (the parent dir whose children are the constellation workspaces).
        # Walks up from the template's directory looking for the first ancestor
        # that contains multiple pangea.yml siblings. Returns nil if none.
        def self.workspaces_root_for(template_file)
          start = File.expand_path(File.dirname(template_file))
          Pathname.new(start).ascend do |path|
            parent = path.parent
            return parent.to_s if siblings_with_pangea_yml(parent) >= 2
          end
          nil
        end

        def self.siblings_with_pangea_yml(parent_path)
          return 0 unless parent_path.directory?

          parent_path.children.count do |child|
            child.directory? && child.join('pangea.yml').file?
          end
        end

        def [](name)
          workspaces[name]
        end

        def include?(name)
          workspaces.key?(name)
        end

        def names
          workspaces.keys
        end

        # Names of workspaces `name` asks from (direct upstream).
        def upstream_of(name)
          ws = workspaces[name] or return []
          ws.upstream_names.select { |n| workspaces.key?(n) }
        end

        # Names of workspaces that ask from `name` (direct downstream).
        def downstream_of(name)
          workspaces.each_value.select do |w|
            w.upstream_names.include?(name)
          end.map(&:name)
        end

        # Transitive closure of `name` in both directions: every workspace
        # that must plan/apply together when user acts on `name`.
        # Returns a Set of names INCLUDING `name` itself.
        #
        # @param max_depth [Integer, nil] if set, limits traversal to that
        #   many hops from `name` (0 = only seed, 1 = seed + direct neighbors,
        #   etc). nil = unlimited (full reachable set).
        def cascade_set(name, max_depth: nil)
          raise MissingWorkspaceError, "unknown workspace: #{name}" unless workspaces.key?(name)

          visited = { name => 0 }
          frontier = [name]
          until frontier.empty?
            n = frontier.shift
            depth = visited[n]
            next if max_depth && depth >= max_depth

            (upstream_of(n) + downstream_of(n)).each do |neighbor|
              next if visited.key?(neighbor)

              visited[neighbor] = depth + 1
              frontier << neighbor
            end
          end
          Set.new(visited.keys)
        end

        # Topologically sort a subset of workspace names — earlier names can
        # run before later ones because no later name asks FROM an earlier one.
        # Kahn's algorithm; raises CycleError if the subset contains a cycle.
        def topo_sort(names_subset)
          subset = names_subset.to_a
          subset_set = Set.new(subset)

          # incoming edges: name -> names_in_subset_this_asks_from
          incoming = subset.each_with_object({}) do |n, h|
            h[n] = upstream_of(n).select { |u| subset_set.include?(u) }
          end

          ready = subset.select { |n| incoming[n].empty? }.sort
          ordered = []
          until ready.empty?
            n = ready.shift
            ordered << n
            subset.each do |m|
              next unless incoming[m].delete(n)

              ready << m if incoming[m].empty?
            end
            ready.sort!
          end

          unless ordered.size == subset.size
            stuck = subset - ordered
            raise CycleError, "reactive ask cycle among: #{stuck.sort.join(', ')}"
          end

          ordered
        end
      end
    end
  end
end
