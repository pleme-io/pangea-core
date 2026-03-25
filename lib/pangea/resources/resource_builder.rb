# frozen_string_literal: true

module Pangea
  module Resources
    # Declarative DSL for defining terraform resource methods.
    #
    # Eliminates the validate→build→return boilerplate that every resource
    # module repeats. Each attribute is classified as:
    #
    #   map:         always set on the resource block
    #   map_present: set only when non-nil
    #   map_bool:    set only when non-nil (explicit boolean check — !val.nil?)
    #   labels:      set when hash is non-empty (.any?)
    #   tags:        set when hash is non-empty (.any?)
    #
    # Usage:
    #   module GoogleComputeNetwork
    #     include Pangea::Resources::ResourceBuilder
    #
    #     define_resource :google_compute_network,
    #       attributes_class: Google::Types::ComputeNetworkAttributes,
    #       outputs: { id: :id, self_link: :self_link },
    #       map: [:name],
    #       map_present: [:project, :description, :routing_mode, :mtu],
    #       map_bool: [:auto_create_subnetworks, :delete_default_routes_on_create]
    #   end
    #
    module ResourceBuilder
      def self.included(base)
        base.extend(ClassMethods)
      end

      module ClassMethods
        # Define a terraform resource method on this module.
        #
        # @param tf_type [Symbol]         Terraform resource type (e.g. :google_compute_network)
        # @param attributes_class [Class]  Dry::Struct class for attribute validation
        # @param outputs [Hash]            { friendly_name => terraform_attribute } — defaults to { id: :id }
        # @param map [Array<Symbol>]       Attributes always set on the resource
        # @param map_present [Array<Symbol>] Attributes set only when non-nil
        # @param map_bool [Array<Symbol>]  Boolean attributes set only when non-nil (uses !val.nil?)
        # @param labels [Symbol, nil]      Attribute name for labels hash (set when .any?)
        # @param tags [Symbol, nil]        Attribute name for tags hash (set when .any?)
        # @param custom_block [Proc]       Optional block receiving (resource_dsl, attrs) for complex resources
        #
        def define_resource(tf_type, attributes_class:, outputs: { id: :id },
                            map: [], map_present: [], map_bool: [],
                            tags: nil, labels: nil, &custom_block)
          @_resource_definitions ||= {}
          @_resource_definitions[tf_type] = _store_definition(attributes_class, outputs, map, map_present, map_bool, tags, labels)

          define_method(tf_type) do |name, attributes = {}|
            attrs = attributes_class.new(attributes)
            _synthesize_block(:resource, tf_type, name, attrs, map, map_present, map_bool, tags, labels, custom_block)
            _build_reference(tf_type.to_s, name, attrs, outputs)
          end
        end

        # Define a terraform data source method on this module.
        #
        # Data sources are read-only lookups. The generated method calls `data()`
        # instead of `resource()` and output references use the `data.` prefix:
        #   ${data.akeyless_secret.my_secret.value}
        #
        # @param tf_type [Symbol]         Terraform data source type (e.g. :akeyless_secret)
        # @param attributes_class [Class]  Dry::Struct class for attribute validation
        # @param outputs [Hash]            { friendly_name => terraform_attribute } — defaults to { id: :id }
        # @param map [Array<Symbol>]       Attributes always set on the data block
        # @param map_present [Array<Symbol>] Attributes set only when non-nil
        # @param map_bool [Array<Symbol>]  Boolean attributes set only when non-nil (uses !val.nil?)
        # @param labels [Symbol, nil]      Attribute name for labels hash (set when .any?)
        # @param tags [Symbol, nil]        Attribute name for tags hash (set when .any?)
        # @param custom_block [Proc]       Optional block receiving (data_dsl, attrs) for complex data sources
        #
        def define_data(tf_type, attributes_class:, outputs: { id: :id },
                        map: [], map_present: [], map_bool: [],
                        tags: nil, labels: nil, &custom_block)
          method_name = :"data_#{tf_type}"
          @_data_definitions ||= {}
          @_data_definitions[tf_type] = _store_definition(attributes_class, outputs, map, map_present, map_bool, tags, labels)

          define_method(method_name) do |name, attributes = {}|
            attrs = attributes_class.new(attributes)
            _synthesize_block(:data, tf_type, name, attrs, map, map_present, map_bool, tags, labels, custom_block)
            _build_reference("data.#{tf_type}", name, attrs, outputs)
          end
        end

        # Introspect registered resource definitions.
        def resource_definitions
          @_resource_definitions || {}
        end

        # Introspect registered data source definitions.
        def data_definitions
          @_data_definitions || {}
        end

        private

        def _store_definition(attributes_class, outputs, map, map_present, map_bool, tags, labels)
          { attributes_class: attributes_class, outputs: outputs, map: map,
            map_present: map_present, map_bool: map_bool, tags: tags, labels: labels }.freeze
        end
      end

      private

      def _synthesize_block(block_type, tf_type, name, attrs, map, map_present, map_bool, tags, labels, custom_block)
        send(block_type, tf_type, name) do
          # Use attrs[attr] (hash-style access) instead of attrs.public_send(attr)
          # to safely handle attribute names that shadow Ruby built-in methods
          # (e.g., :type, :send, :hash, :id, :class, :method, :display, :freeze).
          map.each { |attr| __send__(attr, attrs[attr]) }
          map_present.each { |attr| val = attrs[attr]; __send__(attr, val) if val }
          map_bool.each { |attr| val = attrs[attr]; __send__(attr, val) unless val.nil? }
          if tags
            tag_val = attrs[tags]
            __send__(tags, tag_val) if tag_val&.any?
          end
          if labels
            label_val = attrs[labels]
            __send__(labels, label_val) if label_val&.any?
          end
          instance_exec(self, attrs, &custom_block) if custom_block
        end
      end

      def _build_reference(type_str, name, attrs, outputs)
        output_hash = outputs.each_with_object({}) do |(friendly, tf_attr), h|
          h[friendly] = "${#{type_str}.#{name}.#{tf_attr}}"
        end
        ResourceReference.new(
          type: type_str,
          name: name,
          resource_attributes: attrs.to_h,
          outputs: output_hash
        )
      end
    end
  end
end
