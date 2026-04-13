# frozen_string_literal: true

module Pangea
  module Resources
    # Partitions resource attributes into validated literals and opaque references.
    #
    # Types stay pure — they model the domain (CIDRs, ports, arrays).
    # ResourceInput handles the serialization concern: some values are known
    # at synthesis time (literals), some are opaque (Terraform ${...} refs).
    #
    # Equivalent to Rust's serde boundary: the type is strict, the
    # serialization layer handles the wire format.
    #
    # Equivalent to substrate's convergence typestate: data is tagged with
    # its partition at the boundary, inner types are uncontaminated.
    #
    # Usage (internal to ResourceBuilder — not called directly):
    #   input = ResourceInput.partition(VpcAttributes, { cidr: "10.0.0.0/16", id: "${aws_vpc.x.id}" })
    #   input[:cidr]  # => "10.0.0.0/16" (validated by Dry::Struct)
    #   input[:id]    # => "${aws_vpc.x.id}" (opaque, passed through)
    #   input.to_h    # => { cidr: "10.0.0.0/16", id: "${aws_vpc.x.id}" }
    #
    class ResourceInput
      # Terraform interpolation reference — opaque string resolved at plan time.
      # Strict: must match ${...} syntax exactly. Random strings rejected.
      REF_PATTERN = /\A\$\{.+\}\z/.freeze

      attr_reader :validated, :refs

      # Partition a raw attribute hash into validated literals and opaque refs.
      #
      # Literals are validated strictly by Dry::Struct. Refs are frozen and
      # passed through. Required attributes that carry refs are excluded from
      # validation (they can't be validated at synthesis time — Terraform
      # resolves them at plan time).
      #
      # We use Dry::Struct.load instead of .new for the literals hash because
      # .load bypasses the missing-key check — ref-carrying required fields
      # are intentionally absent from the literals hash.
      #
      # @param attributes_class [Class] Dry::Struct subclass for type validation
      # @param raw_hash [Hash] User-provided attributes (may contain ${...} refs)
      # @return [ResourceInput]
      def self.partition(attributes_class, raw_hash)
        literals = {}
        refs = {}

        raw_hash.each do |k, v|
          sym = k.to_sym
          if v.is_a?(String) && v.match?(REF_PATTERN)
            refs[sym] = v
          else
            literals[sym] = v
          end
        end

        # Validate that every required attribute is accounted for
        # (present in either literals or refs, not missing from both).
        required_keys = attributes_class.schema
          .select { |k| k.required? }
          .map(&:name)
          .to_set

        provided_keys = literals.keys.to_set | refs.keys.to_set
        missing = required_keys - provided_keys
        unless missing.empty?
          raise ArgumentError,
            "#{attributes_class}: missing required attributes #{missing.to_a.inspect}. " \
            "Provide literal values or Terraform references for all required fields."
        end

        # Use .load to bypass Dry::Struct's missing-key enforcement.
        # We've already verified coverage above. Literal values are
        # type-validated; ref-carrying fields are intentionally absent.
        validated = attributes_class.load(literals)
        new(validated, refs.freeze)
      end

      # @param validated [Dry::Struct] Type-validated literal attributes
      # @param refs [Hash{Symbol => String}] Opaque Terraform references
      def initialize(validated, refs)
        @validated = validated
        @refs = refs
        freeze
      end

      # Access an attribute value. Refs take priority over validated literals.
      # This is the serialization merge: opaque values override typed values.
      #
      # @param key [Symbol, String] Attribute name
      # @return [Object] The ref string if present, otherwise the validated value
      def [](key)
        k = key.to_sym
        refs.fetch(k) { validated[k] }
      end

      # Merge validated attrs and refs into a single hash for Terraform JSON.
      # Refs override validated values (they are the source of truth at plan time).
      #
      # @return [Hash]
      def to_h
        validated.to_h.merge(refs)
      end
    end
  end
end
