# frozen_string_literal: true

require_relative 'config'
require_relative 'operations'
require_relative 'reactivity'
require_relative 'theme'

module Pangea
  class CLI
    # Cascade — when the user runs plan/apply/destroy on a template that
    # participates in reactive relationships (declared in pangea.yml's
    # reactivity.asks block), automatically include every transitively
    # reachable workspace, in the right order:
    #
    #   - plan  : topological (upstream first, downstream after)
    #   - apply : topological (upstream must exist before downstream reads)
    #   - destroy: reverse topological (tear down leaves before roots)
    #
    # Each workspace's phase emits a themed section divider plus a
    # structured summary line. Set PANGEA_NO_CASCADE=1 to fall back to
    # single-workspace behavior even when a cascade would otherwise fire.
    class Cascade
      attr_reader :graph, :ordered_names, :seed_name, :seed_template_file,
                  :outcomes, :max_depth

      def self.enabled?
        ENV['PANGEA_NO_CASCADE'] != '1'
      end

      # Build a cascade plan from a user-provided template file path. Returns
      # nil if:
      #  - cascade is disabled (PANGEA_NO_CASCADE=1)
      #  - the template is not in a scannable constellation
      #  - the resolved cascade has only the seed itself (depth 0, or no
      #    reactive neighbors in range)
      #
      # Depth resolution (first match wins):
      #  1. explicit `max_depth:` argument (CLI --depth N)
      #  2. ENV['PANGEA_CASCADE_DEPTH']
      #  3. workspace or root pangea.yml `cascade.default_depth`
      #  4. nil (unlimited — the full transitive closure)
      def self.for_template(template_file, max_depth: nil)
        return nil unless enabled?

        workspaces_root = Reactivity::Graph.workspaces_root_for(template_file)
        return nil unless workspaces_root

        graph = Reactivity::Graph.scan(workspaces_root)
        seed_dir = File.dirname(File.expand_path(template_file))
        seed_name = File.basename(seed_dir)

        return nil unless graph.include?(seed_name)

        depth = resolve_depth(
          explicit: max_depth,
          seed_dir: seed_dir,
          workspaces_root: workspaces_root,
        )

        cascade_names = graph.cascade_set(seed_name, max_depth: depth)
        return nil if cascade_names.size <= 1

        ordered = graph.topo_sort(cascade_names)
        new(
          graph: graph,
          ordered_names: ordered,
          seed_name: seed_name,
          seed_template_file: File.expand_path(template_file),
          max_depth: depth,
        )
      end

      # Resolve the depth cap from CLI arg → env → workspace yml → root yml.
      # Returns nil for unlimited. A non-numeric / negative value falls
      # through to the next source.
      def self.resolve_depth(explicit:, seed_dir:, workspaces_root:)
        candidates = [
          explicit,
          parse_int(ENV['PANGEA_CASCADE_DEPTH']),
          yaml_depth(File.join(seed_dir, 'pangea.yml')),
          yaml_depth(File.join(File.dirname(workspaces_root), 'pangea.yml')),
        ]
        candidates.find { |d| !d.nil? }
      end

      def self.parse_int(value)
        return nil if value.nil?
        return value.negative? ? nil : value if value.is_a?(Integer)
        return nil if value.to_s.strip.empty?

        i = Integer(value.to_s, 10)
        i.negative? ? nil : i
      rescue ArgumentError, TypeError
        nil
      end

      def self.yaml_depth(path)
        return nil unless File.exist?(path)

        config = YAML.safe_load(File.read(path)) || {}
        parse_int(config.dig('cascade', 'default_depth'))
      rescue StandardError
        nil
      end

      def initialize(graph:, ordered_names:, seed_name:, seed_template_file:, max_depth: nil)
        @graph = graph
        @ordered_names = ordered_names
        @seed_name = seed_name
        @seed_template_file = seed_template_file
        @max_depth = max_depth
        @outcomes = []
      end

      # Run plan across every cascaded workspace in topological order.
      # Upstream fails → we continue anyway so the user sees what else drifts.
      def plan(namespace: nil)
        announce(:plan)
        each_stage(ordered_names, primary: :plan) { |ops| ops.plan }
      end

      # Apply in topological order; abort the cascade on the first failure
      # since downstream reads assume upstream state.
      def apply(namespace: nil)
        announce(:apply)
        each_stage(ordered_names, primary: :apply, abort_on_failure: true) { |ops| ops.apply }
      end

      # Destroy in reverse topological order.
      def destroy(namespace: nil)
        announce(:destroy)
        each_stage(ordered_names.reverse, primary: :destroy) { |ops| ops.destroy }
      end

      private

      def announce(op)
        t = Theme
        t.section("cascade #{op}")
        parts = [
          [:info, 'Seed'],
          [:resource, seed_name],
          [:info, '→'],
          [:count, ordered_names.size.to_s],
          [:info, 'workspace(s)'],
        ]
        if max_depth
          parts.concat([[:info, 'depth'], [:count, max_depth.to_s]])
        end
        t.structured_log(*parts)
        t.structured_log(
          [:info, 'Order'],
          [:path, ordered_names.join(' → ')],
        )
      end

      def each_stage(names, primary:, abort_on_failure: false)
        failures = []
        names.each_with_index do |name, i|
          workspace = graph[name]
          template_file = detect_template(workspace)
          next unless template_file

          stage_banner(name, i + 1, names.size)
          ops = nil
          begin
            config = Config.new(template_file, namespace: nil)
            ops = Operations.new(config)
            run_actions(ops, workspace.pre_actions, primary, :pre)
            yield ops
            run_actions(ops, workspace.post_actions, primary, :post)
            record_outcome(ops)
          rescue StandardError => e
            record_outcome(ops, fallback_name: name, error: e)
            failures << [name, e]
            if abort_on_failure
              Theme.log("cascade aborted at #{name}: #{e.message}", level: :error)
              break
            else
              Theme.log("stage #{name} failed: #{e.message}", level: :warning)
            end
          end
        end

        render_recap
        unless failures.empty?
          Theme.log(
            "cascade completed with #{failures.size} failure(s): #{failures.map(&:first).join(', ')}",
            level: :warning,
          )
        end
        failures.empty?
      end

      # Execute declared pre/post actions at the current cascade visit.
      # Silently skips actions that would conflict with the primary command
      # (belt-and-suspenders — Workspace.load already rejects them).
      def run_actions(ops, actions, primary, position)
        return if actions.nil? || actions.empty?

        primary_s = primary.to_s
        actions.each do |action|
          next if action == primary_s

          Theme.structured_log(
            [:divider, "  cascade.#{position}_action"],
            [:info, action],
          )
          case action
          when 'synth'  then ops.synth
          when 'output' then ops.output
          when 'init'   then ops.init
          end
        end
      end

      # Capture the StageOutcome from an Operations instance; fall back to
      # a synthetic "failed before counts" outcome when the stage raised
      # before Operations#run_tofu populated last_outcome.
      def record_outcome(ops, fallback_name: nil, error: nil)
        outcome = ops&.last_outcome
        outcome ||= Operations::StageOutcome.new(
          operation: 'unknown',
          workspace: fallback_name || ops&.config&.template_name,
          success: error.nil?,
          added: 0, changed: 0, removed: 0,
          transient_errors: 0, dropped_warnings: 0,
          error: error&.message,
        )
        @outcomes << outcome
      end

      # Themed recap table: one row per stage with counts + status.
      def render_recap
        return if outcomes.empty?

        t = Theme
        t.section('cascade recap')

        totals = { added: 0, changed: 0, removed: 0, failed: 0, transient: 0 }
        outcomes.each do |o|
          totals[:added]     += o.added.to_i
          totals[:changed]   += o.changed.to_i
          totals[:removed]   += o.removed.to_i
          totals[:failed]    += 1 unless o.success
          totals[:transient] += o.transient_errors.to_i
        end

        outcomes.each do |o|
          status_role = if !o.success then :error
                        elsif o.transient_errors.to_i.positive? then :transient
                        elsif o.total_changes.zero? then :noop
                        else :success
                        end
          status_glyph = case status_role
                         when :error     then '✗'
                         when :transient then '⚠'
                         when :noop      then '='
                         else                 '✔'
                         end
          t.structured_log(
            [status_role, status_glyph],
            [:resource, o.workspace.to_s.ljust(24)],
            [:info, o.operation.to_s.ljust(7)],
            [:create, "+#{o.added.to_i}"],
            [:update, "~#{o.changed.to_i}"],
            [:delete, "-#{o.removed.to_i}"],
            marker_level: status_role == :error ? :error : :info,
          )
        end

        t.structured_log(
          [:heading, 'Total:'],
          [:create, "+#{totals[:added]} added"],
          [:update, "~#{totals[:changed]} changed"],
          [:delete, "-#{totals[:removed]} destroyed"],
          [:error, "✗#{totals[:failed]} failed"],
          [:transient, "⚠#{totals[:transient]} transient"],
          marker_level: totals[:failed].positive? ? :error : :heading,
        )
      end

      # A workspace dir contains one or more .rb templates alongside
      # pangea.yml. Pick the one whose basename matches the workspace name
      # with hyphens -> underscores; fall back to the first *.rb file.
      def detect_template(workspace)
        preferred = File.join(workspace.dir, "#{workspace.name.tr('-', '_')}.rb")
        return preferred if File.exist?(preferred)

        candidates = Dir.glob(File.join(workspace.dir, '*.rb')).sort
        candidates.first
      end

      def stage_banner(name, idx, total)
        t = Theme
        t.structured_log(
          [:divider, "── [#{idx}/#{total}]"],
          [:resource, name],
          [:divider, '──────────────────'],
        )
      end
    end
  end
end
