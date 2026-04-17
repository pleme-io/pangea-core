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
      attr_reader :graph, :ordered_names, :seed_name, :seed_template_file

      def self.enabled?
        ENV['PANGEA_NO_CASCADE'] != '1'
      end

      # Build a cascade plan from a user-provided template file path. Returns
      # nil if the template is not in a scannable constellation OR if the
      # only reachable workspace is the seed itself (no cascade needed).
      def self.for_template(template_file)
        return nil unless enabled?

        workspaces_root = Reactivity::Graph.workspaces_root_for(template_file)
        return nil unless workspaces_root

        graph = Reactivity::Graph.scan(workspaces_root)
        seed_dir = File.dirname(File.expand_path(template_file))
        seed_name = File.basename(seed_dir)

        return nil unless graph.include?(seed_name)

        cascade_names = graph.cascade_set(seed_name)
        return nil if cascade_names.size <= 1

        ordered = graph.topo_sort(cascade_names)
        new(
          graph: graph,
          ordered_names: ordered,
          seed_name: seed_name,
          seed_template_file: File.expand_path(template_file),
        )
      end

      def initialize(graph:, ordered_names:, seed_name:, seed_template_file:)
        @graph = graph
        @ordered_names = ordered_names
        @seed_name = seed_name
        @seed_template_file = seed_template_file
      end

      # Run plan across every cascaded workspace in topological order.
      # Upstream fails → we continue anyway so the user sees what else drifts.
      def plan(namespace: nil)
        announce(:plan)
        each_stage(ordered_names) { |ops| ops.plan }
      end

      # Apply in topological order; abort the cascade on the first failure
      # since downstream reads assume upstream state.
      def apply(namespace: nil)
        announce(:apply)
        each_stage(ordered_names, abort_on_failure: true) { |ops| ops.apply }
      end

      # Destroy in reverse topological order.
      def destroy(namespace: nil)
        announce(:destroy)
        each_stage(ordered_names.reverse) { |ops| ops.destroy }
      end

      private

      def announce(op)
        t = Theme
        t.section("cascade #{op}")
        t.structured_log(
          [:info, 'Seed'],
          [:resource, seed_name],
          [:info, '→'],
          [:count, ordered_names.size.to_s],
          [:info, 'workspace(s)'],
        )
        t.structured_log(
          [:info, 'Order'],
          [:path, ordered_names.join(' → ')],
        )
      end

      def each_stage(names, abort_on_failure: false)
        failures = []
        names.each_with_index do |name, i|
          workspace = graph[name]
          template_file = detect_template(workspace)
          next unless template_file

          stage_banner(name, i + 1, names.size)
          begin
            config = Config.new(template_file, namespace: nil)
            ops = Operations.new(config)
            yield ops
          rescue StandardError => e
            failures << [name, e]
            if abort_on_failure
              Theme.log("cascade aborted at #{name}: #{e.message}", level: :error)
              break
            else
              Theme.log("stage #{name} failed: #{e.message}", level: :warning)
            end
          end
        end

        unless failures.empty?
          Theme.log(
            "cascade completed with #{failures.size} failure(s): #{failures.map(&:first).join(', ')}",
            level: :warning,
          )
        end
        failures.empty?
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
