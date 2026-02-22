# frozen_string_literal: true

require 'dry-struct'

module Pangea
  module Resources
    # Base class for all provider resource attribute structs.
    #
    # Provides:
    # - transform_keys(&:to_sym) so hash keys are normalized
    # - T constant aliasing Resources::Types for short, unambiguous type references
    #
    # All provider attribute classes should inherit from this:
    #   class VpcAttributes < Pangea::Resources::BaseAttributes
    #     attribute :cidr_block, T::CidrBlock
    #     attribute :tags, T::AwsTags.default({}.freeze)
    #   end
    #
    class BaseAttributes < Dry::Struct
      # Short alias for Pangea::Resources::Types — works inside class bodies
      # because it's a real constant (not const_missing-based)
      T = Pangea::Resources::Types

      transform_keys(&:to_sym)

      # Terraform reference pattern — matches ${...} interpolation syntax.
      # Use in self.new validators to skip format checks on values that are
      # terraform references (they will be resolved at plan/apply time).
      TERRAFORM_REF_PATTERN = /\$\{.*\}/.freeze

      # Returns true if the value contains a terraform/HCL interpolation reference.
      # Works for both class-level (self.terraform_reference?) and instance-level usage.
      def self.terraform_reference?(value)
        return false unless value.is_a?(String)

        value.match?(TERRAFORM_REF_PATTERN)
      end

      def terraform_reference?(value)
        self.class.terraform_reference?(value)
      end

      # Dry::Struct uses `new` to create copies with merged attributes.
      # Alias `copy_with` for backward compatibility with existing code.
      def copy_with(changes = {})
        self.class.new(to_h.merge(changes))
      end
    end
  end
end
