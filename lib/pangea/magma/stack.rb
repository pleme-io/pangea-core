# frozen_string_literal: true

require_relative 'chain'
require_relative 'distribution'
require_relative 'optimization'
require_relative 'orchestrator'
require_relative 'workspace'

module Pangea
  module Magma
    # Stack — the high-level "give me a typed orchestrator for these
    # workspaces with these edges" helper. Bundles Distribution +
    # Chain + Orchestrator declaration into one call so per-workspace
    # `.magma.rb` files don't repeat the same wiring template across
    # the fleet.
    #
    # Authors:
    #
    #   STACK = Pangea::Magma::Stack.build(
    #     name: :k3s_stack,
    #     tiers: {
    #       permissions: [K3S_PERMISSIONS_WORKSPACE],
    #       cluster:     [K3S_CLUSTER_WORKSPACE],
    #     },
    #     edges: [
    #       { from: :k3s_permissions, output: :instance_profile_name,
    #         to:   :k3s_cluster,     input:  :instance_profile_name },
    #       { from: :k3s_permissions, output: :node_role_name,
    #         to:   :k3s_cluster,     input:  :node_role_name },
    #     ],
    #     optimization: Pangea::Magma::Optimization.parallel_by_tier,
    #     attestation:  { enabled: true, chain: 'tameshi' },
    #   )
    #
    #   STACK.chain         # → Pangea::Magma::Chain
    #   STACK.orchestrator  # → Pangea::Magma::Orchestrator
    #   STACK.deploy!       # convenience for STACK.orchestrator.deploy!
    #
    # Per theory/PANGEA-MAGMA-ORCHESTRATION.md §III.6.
    class Stack
      attr_reader :name, :chain, :orchestrator, :distribution, :optimization, :attestation

      class << self
        def build(name:, tiers:, edges: [], optimization: nil, attestation: {})
          opt = case optimization
                when Pangea::Magma::Optimization then optimization
                when Hash                        then Pangea::Magma::Optimization.declare(**optimization)
                when nil                         then nil
                else
                  raise ArgumentError, "optimization must be Optimization|Hash|nil, got #{optimization.class}"
                end

          flat_workspaces = tiers.values.flatten
          by_name         = flat_workspaces.to_h { |w| [w.name, w] }

          # Auto-derive tier edges only when no explicit edges given.
          tier_edges = edges.empty? ? auto_tier_edges(tiers) : edges

          chain = Pangea::Magma::Chain.build(optimization: opt) do |c|
            flat_workspaces.each { |w| c.workspace w }
            tier_edges.each do |e|
              from = by_name.fetch(e.fetch(:from).to_sym) {
                raise ArgumentError, "edge.from references unknown workspace: #{e[:from]}"
              }
              to   = by_name.fetch(e.fetch(:to).to_sym) {
                raise ArgumentError, "edge.to references unknown workspace: #{e[:to]}"
              }
              c.edge from: from, output: e.fetch(:output),
                     to:   to,   input:  e.fetch(:input)
            end
          end

          distribution = Pangea::Magma::Distribution.declare(
            strategy: :tier_separation,
            tiers:    tiers,
            edges:    tiers_to_distribution_edges(tiers),
            placement: tiers.transform_values { {} },
          )

          orchestrator = Pangea::Magma::Orchestrator.new(
            distribution: distribution,
            optimization: opt,
            attestation:  attestation,
          )

          new(name: name.to_sym, chain: chain, orchestrator: orchestrator,
              distribution: distribution, optimization: opt,
              attestation: attestation)
        end

        private

        # Auto-derive cross-tier edges by matching upstream tier
        # outputs to identically-named downstream tier inputs. Two
        # tiers' workspaces with the same slot name → typed edge.
        def auto_tier_edges(tiers)
          tier_names  = tiers.keys
          edges       = []
          tier_names.each_with_index do |upstream_tier, idx|
            next if idx + 1 >= tier_names.size

            downstream_tier = tier_names[idx + 1]
            tiers[upstream_tier].each do |upstream_ws|
              tiers[downstream_tier].each do |downstream_ws|
                upstream_ws.outputs.each do |out_name, _slot|
                  next unless downstream_ws.inputs.key?(out_name)

                  edges << {
                    from:   upstream_ws.name, output: out_name,
                    to:     downstream_ws.name, input: out_name,
                  }
                end
              end
            end
          end
          edges
        end

        # Distribution#tier_separation expects a Hash of
        # `upstream_tier => downstream_tier` mapping. Build it
        # mechanically from the ordering of `tiers.keys`.
        def tiers_to_distribution_edges(tiers)
          keys = tiers.keys
          keys.each_cons(2).each_with_object({}) do |(a, b), acc|
            acc[a] = b
          end
        end
      end

      def initialize(name:, chain:, orchestrator:, distribution:,
                     optimization:, attestation:)
        @name         = name
        @chain        = chain
        @orchestrator = orchestrator
        @distribution = distribution
        @optimization = optimization
        @attestation  = attestation
      end

      def deploy!(only: nil)
        @orchestrator.deploy!(only: only)
      end

      def to_h
        {
          name:         @name.to_s,
          chain:        @chain.to_h,
          distribution: @distribution.to_h,
          optimization: @optimization&.to_h,
          attestation:  @attestation,
        }
      end

      def to_json(*args)
        to_h.to_json(*args)
      end
    end
  end
end
