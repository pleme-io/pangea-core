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
    # A ref is opaque at whatever DEPTH it sits. These are all the same fact —
    # a value Terraform will not resolve until plan time:
    #
    #   firewall_id: "${hcloud_firewall.main.id}"            # scalar
    #   server_ids:  ["${hcloud_server.a.id}", ...]          # array element
    #   network:     [{ network_id: "${hcloud_network.x.id}" }]  # block field
    #   matrix:      [[1, "${var.x}"]]                       # nested
    #
    # So containment is the routing predicate, not identity: an attribute whose
    # value CONTAINS a ref anywhere is routed to `refs` and passes through
    # verbatim (order and structure preserved — Terraform needs the whole list,
    # and a partial list is not a thing you can emit).
    #
    # Bypassing the ref is the only thing that is bypassed. Everything AROUND
    # an opaque leaf is still known at synthesis time, so it is still checked
    # (`check_residual`): `[server.id, "not-a-number"]` on an integer-typed list
    # still raises. Skipping the literal element would be its own defect —
    # type-checking is bypassed because a `${...}` CANNOT be decided, never
    # because deciding is inconvenient.
    #
    class ResourceInput
      # Terraform interpolation reference — opaque string resolved at plan time.
      # Strict: must match ${...} syntax exactly. Random strings rejected.
      REF_PATTERN = /\A\$\{.+\}\z/.freeze

      # Decorator layers (Constrained / Default / Lax / Constructor / Sum) we
      # are willing to peel while looking for a container type. Past this we
      # stop claiming to know anything about the contents.
      MAX_TYPE_UNWRAP_DEPTH = 8

      attr_reader :validated, :refs

      # True when the value IS an opaque Terraform reference.
      #
      # @param value [Object]
      # @return [Boolean]
      def self.ref?(value)
        value.is_a?(::String) && value.match?(REF_PATTERN)
      end

      # True when the value CONTAINS an opaque Terraform reference at any depth.
      # This is the routing predicate: containment, not identity.
      #
      # @param value [Object]
      # @return [Boolean]
      def self.contains_ref?(value)
        case value
        when ::String then ref?(value)
        when ::Array  then value.any? { |el| contains_ref?(el) }
        when ::Hash   then value.any? { |k, v| contains_ref?(k) || contains_ref?(v) }
        else false
        end
      end

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
          if contains_ref?(v)
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

          check_value(type, value, attributes_class, key)
        end

        # Ref-CARRYING containers still get everything-but-the-ref checked.
        # A whole-value ref (`firewall_id: "${...}"`) has nothing around it.
        refs.each do |key, value|
          next if ref?(value)

          check_residual(schema_keys[key], value, attributes_class, key)
        end

        # .load bypasses missing-key enforcement (refs are intentionally absent)
        # but we've validated every literal value above.
        validated = attributes_class.load(literals)
        new(validated, refs.freeze)
      end

      # Validate one fully-known value against its declared type.
      # Errors are re-raised with the attribute name attached.
      #
      # NOTE: the coerced result is deliberately discarded. `Dry::Struct.load`
      # does not coerce either, so the partition boundary is validate-only in
      # BOTH directions — a literal and a ref-adjacent leaf are treated alike.
      def self.check_value(type, value, attributes_class, key)
        type.call(value)
      rescue Dry::Types::ConstraintError, Dry::Types::CoercionError => e
        raise e.class, "#{attributes_class}: attribute :#{key} — #{e.message}"
      end
      private_class_method :check_value

      # Validate everything inside `value` that is NOT an opaque ref, against
      # whatever part of `type` declares it.
      #
      # Opaque leaves are skipped — undecidable until Terraform resolves them.
      # Every other leaf is decidable, so a bad one is a normal type error.
      #
      # Honest limits (nothing silently weakened beyond these):
      #   * a `.constrained(min_size:)`-style predicate on the CONTAINER is not
      #     re-applied to a ref-carrying container — re-checking it would risk
      #     false rejections from element-inspecting predicates.
      #   * a type that declares nothing about its contents (bare `T::Hash`,
      #     bare `T::Array`) has nothing to check, so skipping is exactly what
      #     the type says — not a hole.
      def self.check_residual(type, value, attributes_class, key)
        return if type.nil?
        return if ref?(value)
        return check_value(type, value, attributes_class, key) unless contains_ref?(value)

        case value
        when ::Array
          member = array_member_type(type)
          return if member.nil?

          value.each { |el| check_residual(member, el, attributes_class, key) }
        when ::Hash
          if (kv = map_key_value_types(type))
            key_type, value_type = kv
            value.each do |k, v|
              check_value(key_type, k, attributes_class, key) if key_type && !ref?(k)
              check_residual(value_type, v, attributes_class, key)
            end
          elsif (key_types = schema_key_types(type))
            value.each { |k, v| check_residual(key_types[k.to_sym], v, attributes_class, key) }
          end
        end
      end
      private_class_method :check_residual

      # Peel decorator layers (Constrained / Default / Lax / Constructor) and
      # Sum arms (`.optional`) until a type that declares its own contents is
      # reached. Returns nil when the type declares no inner structure.
      def self.structural_type(type, depth = 0)
        return nil if type.nil? || depth > MAX_TYPE_UNWRAP_DEPTH
        return type if type.is_a?(Dry::Types::Array::Member) ||
                       type.is_a?(Dry::Types::Map) ||
                       type.is_a?(Dry::Types::Schema)

        if type.respond_to?(:left) && type.respond_to?(:right)
          return structural_type(type.left, depth + 1) || structural_type(type.right, depth + 1)
        end

        return nil unless type.respond_to?(:type)

        inner = type.type
        return nil if inner.nil? || inner.equal?(type)

        structural_type(inner, depth + 1)
      end
      private_class_method :structural_type

      # Declared member type of an array type, or nil.
      def self.array_member_type(type)
        structural = structural_type(type)
        structural.is_a?(Dry::Types::Array::Member) ? structural.member : nil
      end
      private_class_method :array_member_type

      # [key_type, value_type] of a `Hash.map(K, V)` type, or nil.
      def self.map_key_value_types(type)
        structural = structural_type(type)
        structural.is_a?(Dry::Types::Map) ? [structural.key_type, structural.value_type] : nil
      end
      private_class_method :map_key_value_types

      # { key_name => declared_type } of a `Hash.schema(...)` type, or nil.
      def self.schema_key_types(type)
        structural = structural_type(type)
        return nil unless structural.is_a?(Dry::Types::Schema)

        structural.keys.each_with_object({}) { |k, h| h[k.name] = k.type }
      end
      private_class_method :schema_key_types

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
