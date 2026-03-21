# frozen_string_literal: true

module Pangea
  module Tagging
    # Enforces tagging policies across all resources in an architecture.
    #
    # Usage:
    #   policy = TaggingPolicy.new(
    #     required_keys: %w[ManagedBy Purpose Environment Team Cluster PangeaFingerprint],
    #     forbidden_values: { ManagedBy: ['manual', 'unknown'] },
    #   )
    #   policy.validate!(resource_tags) # raises on violation
    #   policy.compliant?(resource_tags) # returns boolean
    #
    class TaggingPolicy
      attr_reader :required_keys, :forbidden_values, :max_tag_count

      def initialize(required_keys: [], forbidden_values: {}, max_tag_count: 50)
        @required_keys = required_keys.map(&:to_s).freeze
        @forbidden_values = forbidden_values.transform_keys(&:to_s).freeze
        @max_tag_count = max_tag_count
      end

      # Validate tags, raising on violation
      def validate!(tags, resource_name: 'unknown')
        violations = check(tags)
        return if violations.empty?

        msg = violations.map { |v| "  - #{v}" }.join("\n")
        raise TaggingViolation, "Resource '#{resource_name}' tagging violations:\n#{msg}"
      end

      # Check compliance without raising
      def compliant?(tags)
        check(tags).empty?
      end

      # Return list of violations (empty = compliant)
      def check(tags)
        tag_hash = normalize_tags(tags)
        violations = []

        required_keys.each do |key|
          unless tag_hash.key?(key)
            violations << "Missing required tag: #{key}"
          end
        end

        forbidden_values.each do |key, forbidden|
          if tag_hash.key?(key) && forbidden.include?(tag_hash[key])
            violations << "Forbidden value '#{tag_hash[key]}' for tag '#{key}'"
          end
        end

        if tag_hash.length > max_tag_count
          violations << "Too many tags: #{tag_hash.length} (max: #{max_tag_count})"
        end

        violations
      end

      # Default policy for Pangea-managed infrastructure
      def self.default
        new(
          required_keys: %w[ManagedBy Purpose Environment Team PangeaFingerprint],
          forbidden_values: {
            'ManagedBy' => %w[manual unknown],
            'Environment' => %w[],
          },
        )
      end

      # Strict policy with cluster identification
      def self.strict
        new(
          required_keys: %w[ManagedBy Purpose Environment Team Cluster PangeaFingerprint PangeaFingerprintFull PangeaArchitecture],
          forbidden_values: {
            'ManagedBy' => %w[manual unknown terraform],
          },
        )
      end

      private

      def normalize_tags(tags)
        tags.transform_keys(&:to_s)
      end
    end

    class TaggingViolation < StandardError; end
  end
end
