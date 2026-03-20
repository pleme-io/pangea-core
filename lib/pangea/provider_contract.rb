# frozen_string_literal: true

module Pangea
  # Contract that all provider modules must satisfy.
  # Validates that a provider gem exposes the expected interface
  # for cross-provider composition in pangea-architectures.
  #
  # Usage:
  #   Pangea::ProviderContract.validate!(Pangea::Resources::AWS)
  #
  module ProviderContract
    class ViolationError < StandardError; end

    # Validate that a module satisfies the provider contract.
    #
    # A valid provider module must:
    # 1. Be a Module (not a Class)
    # 2. Define at least one resource method (matching its prefix)
    # 3. Be extendable onto a synthesizer object
    #
    # @param provider_module [Module] The provider module to validate
    # @param prefix [String] Expected resource method prefix (e.g., 'aws_')
    # @raise [ViolationError] if the contract is not satisfied
    def self.validate!(provider_module, prefix: nil)
      unless provider_module.is_a?(Module) && !provider_module.is_a?(Class)
        raise ViolationError, "#{provider_module} must be a Module, got #{provider_module.class}"
      end

      if prefix
        methods = provider_module.instance_methods(false)
        matching = methods.select { |m| m.to_s.start_with?(prefix) }
        if matching.empty?
          raise ViolationError, "#{provider_module} has no methods starting with '#{prefix}'"
        end
      end
    end

    # Check without raising — returns [valid?, errors]
    def self.check(provider_module, prefix: nil)
      validate!(provider_module, prefix: prefix)
      [true, []]
    rescue ViolationError => e
      [false, [e.message]]
    end

    # Provider metadata for introspection
    module Metadata
      def provider_prefix
        raise NotImplementedError, "#{self} must define provider_prefix"
      end

      def resource_count
        instance_methods(false).count { |m| m.to_s.start_with?(provider_prefix) }
      end

      def resource_names
        instance_methods(false).select { |m| m.to_s.start_with?(provider_prefix) }.sort
      end
    end
  end
end
