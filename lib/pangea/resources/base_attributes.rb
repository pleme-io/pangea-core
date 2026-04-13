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

      # Override new to handle Terraform interpolation references on
      # complex-typed attributes (Array, Hash). When a Terraform ref string
      # like "${aws_route53_zone.x.name_servers}" is passed where an Array
      # is expected, Dry::Struct's schema resolver rejects it before we can
      # intercept. This override wraps ref strings in an Array so they pass
      # type validation — Terraform resolves them at plan/apply time.
      #
      # This is the systemic equivalent of Rust's newtype pattern with
      # From<T> impl: the type boundary enforces invariants for literal
      # values while transparently converting known-valid reference forms.
      def self.new(attributes = {})
        return super if attributes.is_a?(self)

        hash = attributes.is_a?(Hash) ? attributes.dup : attributes.to_h.dup
        hash.transform_keys!(&:to_sym)

        # For each attribute, if the schema expects Array/Hash but the value
        # is a Terraform ref string, wrap it so Dry::Types doesn't reject it.
        schema.each do |key|
          attr_name = key.name
          value = hash[attr_name]
          next unless value.is_a?(String) && value.match?(TERRAFORM_REF_PATTERN)

          # Check if the declared type expects an Array or Hash
          type_str = key.type.to_s
          if type_str.include?('Array') || type_str.include?('Hash')
            hash[attr_name] = [value]
          end
        end

        super(hash)
      end

      # Override in subclasses to use a different reference pattern
      # (e.g., Pulumi uses different interpolation syntax).
      def self.reference_pattern
        TERRAFORM_REF_PATTERN
      end

      # Returns true if the value contains a terraform/HCL interpolation reference.
      # Works for both class-level (self.terraform_reference?) and instance-level usage.
      # Uses the overridable reference_pattern so providers can customize detection.
      def self.terraform_reference?(value)
        return false unless value.is_a?(String)

        value.match?(reference_pattern)
      end

      def terraform_reference?(value)
        self.class.terraform_reference?(value)
      end

      # Yields the attribute value if it's NOT a terraform reference,
      # otherwise returns the raw reference string. Useful when a resource
      # needs to compute/transform a value but must pass through ${...} refs.
      #
      #   terraform_ref_or(:cidr_block) { |v| calculate_something(v) }
      #
      def terraform_ref_or(attr_name)
        val = public_send(attr_name)
        terraform_reference?(val) ? val : yield(val)
      end

      # Create a copy with merged attributes.
      # Uses Dry::Struct's load method to bypass custom self.new overrides,
      # preventing infinite recursion when copy_with is called inside validators.
      def copy_with(changes = {})
        merged = to_h.merge(changes.transform_keys(&:to_sym))
        self.class.load(merged)
      end
    end
  end
end
