# frozen_string_literal: true

require 'digest'
require 'json'

module Pangea
  module Tagging
    # Generates a cryptographic fingerprint from deployment configuration.
    #
    # The fingerprint is a SHA-256 hash of the canonical JSON representation
    # of the deployment config. This fingerprint is applied as a tag to every
    # resource, enabling cryptographic verification that a resource belongs
    # to a specific infrastructure deployment.
    #
    # Usage:
    #   fp = Fingerprint.new(
    #     cluster_name: 'zek-dev',
    #     account_id: '123456789012',
    #     region: 'us-east-1',
    #     architecture: 'k3s_dev_cluster',
    #     version: '1.0.0',
    #   )
    #   fp.hex        # => "a1b2c3d4..." (64-char hex)
    #   fp.short      # => "a1b2c3d4" (8-char prefix)
    #   fp.tags       # => base tags + fingerprint tag
    #   fp.verify?(tags) # => true if tags contain matching fingerprint
    #
    class Fingerprint
      ALGORITHM = 'SHA-256'
      TAG_KEY = 'PangeaFingerprint'
      SHORT_LENGTH = 8

      attr_reader :config, :hex

      def initialize(**config)
        @config = config.sort.to_h.freeze
        @hex = compute_hash.freeze
      end

      # Short fingerprint (8 chars) for human readability
      def short
        hex[0, SHORT_LENGTH]
      end

      # Full tag set including fingerprint
      def tags(extra = {})
        base_tags.merge(extra).merge(
          TAG_KEY.to_sym => short,
          PangeaFingerprintFull: hex,
          PangeaArchitecture: config[:architecture].to_s,
          PangeaVersion: config[:version].to_s,
        )
      end

      # Verify that a resource's tags match this fingerprint
      def verify?(resource_tags)
        tag_value = resource_tags[TAG_KEY] || resource_tags[TAG_KEY.to_sym]
        tag_value == short
      end

      # Verify full hash (stronger verification)
      def verify_full?(resource_tags)
        tag_value = resource_tags['PangeaFingerprintFull'] || resource_tags[:PangeaFingerprintFull]
        tag_value == hex
      end

      # Generate verification report for a set of resources
      def verification_report(resources_with_tags)
        results = resources_with_tags.map do |name, tags|
          {
            resource: name,
            verified: verify?(tags),
            full_verified: verify_full?(tags),
            fingerprint: tags[TAG_KEY] || tags[TAG_KEY.to_sym],
          }
        end

        {
          expected_fingerprint: short,
          expected_full: hex,
          algorithm: ALGORITHM,
          config_hash: config,
          total: results.length,
          verified: results.count { |r| r[:verified] },
          failed: results.reject { |r| r[:verified] },
          results: results,
        }
      end

      def to_s
        "Fingerprint(#{short}, algorithm=#{ALGORITHM}, config_keys=#{config.keys.join(',')})"
      end

      def ==(other)
        other.is_a?(Fingerprint) && hex == other.hex
      end

      private

      def compute_hash
        canonical = JSON.generate(config, sort: true)
        Digest::SHA256.hexdigest(canonical)
      end

      def base_tags
        {
          ManagedBy: 'pangea',
          Purpose: config[:purpose] || 'infrastructure',
          Environment: config[:environment] || 'development',
          Team: config[:team] || 'platform',
          Cluster: config[:cluster_name].to_s,
        }
      end
    end
  end
end
