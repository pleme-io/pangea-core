# frozen_string_literal: true

require 'json'
require 'open3'
require_relative 'workspace'

module Pangea
  module Magma
    # Typed DAG of Workspaces wired by ChainEdges. Mirrors
    # `magma_pangea::chain::WorkspaceChain` (per theory/MAGMA.md §II.9
    # and theory/PANGEA-MAGMA-ORCHESTRATION.md §III.2).
    #
    # Authors:
    #
    #   chain = Pangea::Magma::Chain.build do |c|
    #     c.workspace vpc       # Pangea::Magma::Workspace instance
    #     c.workspace cluster
    #     c.workspace fluxcd
    #     c.edge from: vpc, output: :vpc_id,
    #            to:   cluster, input: :vpc_id
    #     c.edge from: cluster, output: :kubeconfig,
    #            to:   fluxcd, input: :kubeconfig
    #   end
    #
    #   chain.reconcile_all   # → AggregateReport Hash (via magma flow run)
    class Chain
      ChainEdge = Struct.new(:from, :from_output, :to, :to_input,
                             keyword_init: true) do
        def to_h
          { from: from.to_s, from_output: from_output.to_s,
            to:   to.to_s,   to_input:    to_input.to_s }
        end
      end

      class Builder
        attr_reader :workspaces, :edges
        def initialize
          @workspaces = {}
          @edges      = []
        end

        def workspace(ws)
          unless ws.is_a?(Workspace)
            raise ArgumentError,
                  "expected Pangea::Magma::Workspace, got #{ws.class}"
          end
          @workspaces[ws.name] = ws
          self
        end

        def edge(from:, output:, to:, input:)
          from_name = from.respond_to?(:name) ? from.name : from
          to_name   = to.respond_to?(:name)   ? to.name   : to
          unless @workspaces.key?(from_name)
            raise ArgumentError, "edge.from references unknown workspace: #{from_name}"
          end
          unless @workspaces.key?(to_name)
            raise ArgumentError, "edge.to references unknown workspace: #{to_name}"
          end
          @edges << ChainEdge.new(
            from: from_name, from_output: output,
            to:   to_name,   to_input:    input,
          )
          self
        end
      end

      class << self
        # Build a typed Chain. Yields a Builder; returns a frozen Chain.
        def build(optimization: nil)
          b = Builder.new
          yield b
          new(workspaces: b.workspaces, edges: b.edges,
              optimization: optimization)
        end

        # Compose: produce a Chain from a list of workspaces with no
        # cross-workspace edges (used for "deploy these in sequence
        # without typed-value flow" scenarios).
        def compose(workspaces, output_propagation: :in_memory, optimization: nil)
          b = Builder.new
          workspaces.each { |w| b.workspace(w) }
          new(workspaces: b.workspaces, edges: b.edges,
              output_propagation: output_propagation,
              optimization: optimization)
        end
      end

      attr_reader :workspaces, :edges, :output_propagation, :optimization

      def initialize(workspaces:, edges:, output_propagation: :in_memory,
                     optimization: nil)
        @workspaces         = workspaces.freeze
        @edges              = edges.freeze
        @output_propagation = output_propagation
        @optimization       = optimization
        validate!
      end

      # Return a new Chain with the given optimization hints. Used by
      # Orchestrator to attach Optimization without rebuilding the chain.
      def with_optimization(opt)
        Chain.new(workspaces: @workspaces, edges: @edges,
                  output_propagation: @output_propagation, optimization: opt)
      end

      def node_count
        @workspaces.size
      end

      def edge_count
        @edges.size
      end

      # Topological order across the declared edges.
      # Raises if a cycle is detected.
      def topo_order
        indegree = @workspaces.each_key.to_h { |n| [n, 0] }
        @edges.each { |e| indegree[e.to] += 1 }
        queue = indegree.select { |_, d| d.zero? }.keys
        order = []
        until queue.empty?
          n = queue.shift
          order << n
          @edges.each do |e|
            next unless e.from == n
            indegree[e.to] -= 1
            queue << e.to if indegree[e.to].zero?
          end
        end
        raise "cycle in chain: #{indegree.keys.inspect}" if order.size < @workspaces.size

        order
      end

      # Reconcile every workspace in topological order. Serializes the
      # chain to a flow.json and invokes `magma flow run`; parses the
      # report back. Returns an AggregateReport-shaped Hash.
      def reconcile_all
        flow_hash = {
          workspaces: @workspaces.values.map { |w| { name: w.name.to_s, dir: w.workspace_dir } },
          edges:      @edges.map(&:to_h),
        }
        flow_hash[:optimization] = @optimization.to_h if @optimization
        flow_json = JSON.pretty_generate(flow_hash)
        tmp = Tempfile.new(['magma-chain', '.json'])
        begin
          tmp.write(flow_json)
          tmp.close
          out, err, status = Open3.capture3(Pangea::Magma.binary, 'flow', tmp.path)
          unless status.success?
            raise "magma flow failed (exit #{status.exitstatus}):\n#{err}\n#{out}"
          end
          JSON.parse(out)
        ensure
          tmp.unlink
        end
      end

      # Subset reconciliation — run a slice of the chain with the rest
      # mocked out (downstream-from-stub gets typed values from the
      # `stub_upstream_outputs` map rather than running upstream Workspaces).
      # Mirrors `WorkspaceChain::reconcile_subset` semantics. For M0.1
      # this is a thin wrapper that drives `magma flow` with a reduced
      # workspace set; the typed-value injection lands once magma
      # exposes a `--stubs <json>` flag.
      def reconcile_subset(subset_names, stub_upstream_outputs: {})
        raise NotImplementedError,
              "Chain#reconcile_subset awaits magma's `--stubs` flag (M0.1.x). " \
              "subset_names=#{subset_names.inspect}, " \
              "stub_upstream_outputs=#{stub_upstream_outputs.inspect}"
      end

      def to_h
        h = {
          output_propagation: @output_propagation,
          workspaces:         @workspaces.transform_values(&:to_h),
          edges:              @edges.map(&:to_h),
        }
        h[:optimization] = @optimization.to_h if @optimization
        h
      end

      def to_json(*args)
        to_h.to_json(*args)
      end

      private

      def validate!
        @edges.each do |e|
          unless @workspaces.key?(e.from)
            raise ArgumentError, "edge.from references unknown workspace: #{e.from}"
          end
          unless @workspaces.key?(e.to)
            raise ArgumentError, "edge.to references unknown workspace: #{e.to}"
          end
        end
      end
    end
  end
end

require 'tempfile'
