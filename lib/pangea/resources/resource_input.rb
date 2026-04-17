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
        # Keys with a `.default(...)` type are NOT user-required — Dry::Struct
        # fills them in on `.load` when omitted. `Schema::Key#required?`
        # reports `true` for every attribute regardless of default, so we
        # additionally filter by `k.type.default?`.
        required_keys = attributes_class.schema
          .select { |k| k.required? && !k.type.default? }
          .map(&:name)
          .to_set

        provided_keys = literals.keys.to_set | refs.keys.to_set
        missing = required_keys - provided_keys
        unless missing.empty?
          raise ArgumentError,
            "#{attributes_class}: missing required attributes #{missing.to_a.inspect}. " \
            "Provide literal values or Terraform references for all required fields."
        end

        # Validate each literal value against its declared type.
        # We can't use .new (raises on missing required keys that are refs)
        # and can't use .load (skips ALL validation).
        # Instead: validate each field individually, then load the validated hash.
        schema_keys = attributes_class.schema.each_with_object({}) do |k, h|
          h[k.name] = k.type
        end

        literals.each do |key, value|
          type = schema_keys[key]
          next unless type # unknown keys already caught by ResourceBuilder

          begin
            type.call(value)
          rescue Dry::Types::ConstraintError, Dry::Types::CoercionError => e
            raise e.class, "#{attributes_class}: attribute :#{key} — #{e.message}"
          end
        end

        # .load bypasses missing-key enforcement (refs are intentionally absent)
        # but we've validated every literal value above.
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

      # Template-author DSL: `input.priority` resolves like `input[:priority]`.
      # Refs win over validated literals (same as `[]`). Unknown attribute
      # names fall through to `super` → NoMethodError with full message.
      def method_missing(name, *args)
        if args.empty? && attribute?(name)
          self[name]
        else
          super
        end
      end

      def respond_to_missing?(name, include_private = false)
        attribute?(name) || super
      end

      private

      def attribute?(name)
        refs.key?(name) || validated.respond_to?(name)
      end
    end
  end
end
