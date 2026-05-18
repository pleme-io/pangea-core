# frozen_string_literal: true

require_relative 'chain'
require_relative 'migration'
require_relative 'distribution'

module Pangea
  module Magma
    # The umbrella primitive — composes Workspace + Chain + Migration
    # + Distribution into one operator-facing surface. Per
    # theory/PANGEA-MAGMA-ORCHESTRATION.md §III.6.
    #
    # Authors:
    #
    #   orch = Pangea::Magma::Orchestrator.new(
    #     distribution: dist,
    #     attestation:  { enabled: true },
    #   )
    #
    #   orch.deploy!                     # full reconcile across the distribution
    #   orch.deploy!(only: [:seph_vpc])  # subset
    #   orch.migrate!(migration)         # apply a typed Migration plan
    #   orch.attestation_chain           # aggregated tameshi receipts
    class Orchestrator
      attr_reader :distribution, :optimization, :attestation

      def initialize(distribution:, optimization: nil, attestation: {})
        @distribution = distribution
        @optimization = optimization
        @attestation  = attestation
      end

      # Full reconcile across the distribution. Returns the
      # AggregateReport from `magma flow run`.
      def deploy!(only: nil)
        chain = @distribution.to_chain
        chain = subset_chain(chain, only) if only && !only.empty?
        chain.reconcile_all
      end

      # Apply a typed Migration plan. Routes to Migration#apply! which
      # drives `magma migrate` (M0.2). For M0.1 this raises with the
      # typed plan available for inspection.
      def migrate!(migration)
        migration.plan.apply!
      end

      # Cross-distribution diff — describe what would change if we
      # re-distributed (e.g. tier_separation → per_provider). M0.3
      # implementation; the typed surface ships now.
      def diff(target_distribution:)
        raise NotImplementedError,
              "Orchestrator#diff awaits M0.3 distribution-diff implementation; " \
              "current=#{@distribution.strategy}, " \
              "target=#{target_distribution.strategy}"
      end

      # Aggregate tameshi attestation receipts across every workspace
      # in the distribution. Returns the typed chain Hash. M0.4.
      def attestation_chain
        raise NotImplementedError,
              "Orchestrator#attestation_chain awaits M0.4 magma-attest aggregation"
      end

      def to_h
        {
          distribution: @distribution.to_h,
          optimization: @optimization&.to_h,
          attestation:  @attestation,
        }
      end

      def to_json(*args)
        to_h.to_json(*args)
      end

      private

      # Subset a chain to just the named workspaces (plus the edges
      # whose both endpoints survive the subset).
      def subset_chain(chain, names)
        wanted = names.map(&:to_sym).to_set
        sub_workspaces = chain.workspaces.select { |k, _| wanted.include?(k) }
        sub_edges      = chain.edges.select { |e| wanted.include?(e.from) && wanted.include?(e.to) }
        Chain.new(workspaces: sub_workspaces, edges: sub_edges,
                  output_propagation: chain.output_propagation)
      end
    end
  end
end

require 'set'
