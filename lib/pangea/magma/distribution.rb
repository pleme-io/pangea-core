# frozen_string_literal: true

require 'json'
require_relative 'chain'

module Pangea
  module Magma
    # Strategy for distributing architecture pieces across workspaces.
    # Per theory/PANGEA-MAGMA-ORCHESTRATION.md §III.4. The
    # distribution doesn't change WHAT is deployed — only WHERE it
    # lives in state organization.
    #
    # Authors:
    #
    #   dist = Pangea::Magma::Distribution.declare(
    #     strategy: :tier_separation,
    #     tiers: {
    #       network:  [vpc_ws, dns_ws, lb_ws],
    #       cluster:  [iam_ws, k3s_ws, kms_ws],
    #       workload: [fluxcd_ws, observability_ws],
    #     },
    #     edges: { network: :cluster, cluster: :workload },
    #     placement: {
    #       network:  { region: 'us-east-1' },
    #       cluster:  { region: 'us-east-1' },
    #       workload: { region: 'us-east-1' },
    #     },
    #   )
    #
    #   chain = dist.to_chain
    #
    # Operators migrate between Distribution strategies via
    # Pangea::Magma::Migration (M0.2).
    class Distribution
      STRATEGIES = %i[tier_separation single_workspace per_provider custom].freeze

      class << self
        def declare(strategy:, tiers: {}, edges: {}, placement: {})
          unless STRATEGIES.include?(strategy)
            raise ArgumentError,
                  "unknown strategy #{strategy.inspect}; expected one of #{STRATEGIES.inspect}"
          end
          new(strategy: strategy, tiers: tiers, edges: edges, placement: placement)
        end
      end

      attr_reader :strategy, :tiers, :edges, :placement

      def initialize(strategy:, tiers:, edges:, placement:)
        @strategy  = strategy
        @tiers     = tiers
        @edges     = edges
        @placement = placement
      end

      # Convert the distribution to a Pangea::Magma::Chain.
      # For :tier_separation: build a chain with tier-level edges; each
      # workspace in a tier links to every workspace in the depending
      # tier via the canonical outputs.
      #
      # For M0.1 this is a structural conversion — full typed-output
      # wiring per tier requires the workspaces to declare their I/O
      # slots, which is the M0.1 Workspace.declare path.
      def to_chain
        case @strategy
        when :tier_separation
          tier_separation_chain
        when :single_workspace
          single_workspace_chain
        when :per_provider, :custom
          raise NotImplementedError,
                "Distribution.to_chain(strategy=#{@strategy}) — M0.3"
        end
      end

      def to_h
        {
          strategy:  @strategy.to_s,
          tiers:     @tiers.transform_values { |ws_list| ws_list.map { |w| w.name.to_s } },
          edges:     @edges.transform_keys(&:to_s).transform_values(&:to_s),
          placement: @placement.transform_keys(&:to_s),
        }
      end

      def to_json(*args)
        to_h.to_json(*args)
      end

      private

      def tier_separation_chain
        Chain.build do |c|
          @tiers.each_value { |ws_list| ws_list.each { |w| c.workspace(w) } }
          # M0.1: structural edges from each upstream-tier workspace
          # to each downstream-tier workspace through declared I/O.
          # Authors declare the typed edges explicitly in M0.x once
          # tier-level output projection is defined.
        end
      end

      def single_workspace_chain
        all = @tiers.values.flatten
        Chain.compose(all, output_propagation: :in_memory)
      end
    end
  end
end
