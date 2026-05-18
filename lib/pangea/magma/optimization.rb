# frozen_string_literal: true

require 'json'

module Pangea
  module Magma
    # Typed orchestration hints — how the chain should be executed,
    # not what it executes. Per
    # theory/PANGEA-MAGMA-ORCHESTRATION.md §III.5 (M0.4).
    #
    # Authors:
    #
    #   opt = Pangea::Magma::Optimization.declare(
    #     strategy:        :parallel_by_tier,
    #     max_concurrency: 4,
    #     retries:         { max: 2, backoff_ms: 500 },
    #     timeout_ms:      10 * 60 * 1000,
    #   )
    #
    # The hints serialize into the flow.json that `magma flow run`
    # consumes; on the Rust side they configure the shigoto
    # Scheduler that wraps each workspace as a Job. M0 ships the
    # serialization + validation surface; the scheduler honors them
    # as soon as `magma flow run` lands its shigoto-wrapped apply
    # path (currently plan-only, sequential).
    class Optimization
      STRATEGIES = %i[sequential parallel parallel_by_tier].freeze

      Retries = Struct.new(:max, :backoff_ms, keyword_init: true) do
        def to_h
          { max: max, backoff_ms: backoff_ms }.compact
        end
      end

      class << self
        def declare(strategy: :sequential, max_concurrency: 1,
                    retries: nil, timeout_ms: nil)
          unless STRATEGIES.include?(strategy)
            raise ArgumentError,
                  "unknown strategy #{strategy.inspect}; expected one of #{STRATEGIES.inspect}"
          end
          if max_concurrency < 1
            raise ArgumentError, "max_concurrency must be >= 1 (got #{max_concurrency})"
          end
          retries_obj = retries.is_a?(Hash) ? Retries.new(**retries) : retries

          new(strategy: strategy, max_concurrency: max_concurrency,
              retries: retries_obj, timeout_ms: timeout_ms)
        end

        # Convenience: sequential default — safest, slowest.
        def sequential
          declare(strategy: :sequential, max_concurrency: 1)
        end

        # Convenience: tier-parallel — leaves with no upstream edge run
        # in parallel, downstream tiers wait. Honors the chain's topo
        # order at execution time.
        def parallel_by_tier(max_concurrency: 4, retries: { max: 2, backoff_ms: 500 })
          declare(strategy: :parallel_by_tier,
                  max_concurrency: max_concurrency, retries: retries)
        end
      end

      attr_reader :strategy, :max_concurrency, :retries, :timeout_ms

      def initialize(strategy:, max_concurrency:, retries:, timeout_ms:)
        @strategy        = strategy
        @max_concurrency = max_concurrency
        @retries         = retries
        @timeout_ms      = timeout_ms
      end

      def to_h
        {
          strategy:        @strategy.to_s,
          max_concurrency: @max_concurrency,
          retries:         @retries&.to_h,
          timeout_ms:      @timeout_ms,
        }.compact
      end

      def to_json(*args)
        to_h.to_json(*args)
      end
    end
  end
end
