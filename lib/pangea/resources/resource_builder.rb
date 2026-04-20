# frozen_string_literal: true

module Pangea
  module Resources
    # Declarative DSL for defining terraform resource methods.
    #
    # Types are PURE — they model the domain (CIDRs, ports, arrays).
    # Terraform references are handled at the serialization boundary
    # via ResourceInput, not in the type definitions.
    #
    # Each attribute is classified as:
    #   map:         always set on the resource block
    #   map_present: set only when non-nil
    #   map_bool:    set only when non-nil (explicit boolean check)
    #   labels:      set when hash is non-empty (.any?)
    #   tags:        set when hash is non-empty (.any?)
    #
    module ResourceBuilder
      def self.included(base)
        base.extend(ClassMethods)
      end

      module ClassMethods
        def define_resource(tf_type, attributes_class:, outputs: { id: :id },
                            map: [], map_present: [], map_bool: [],
                            tags: nil, labels: nil, &custom_block)
          @_resource_definitions ||= {}
          @_resource_definitions[tf_type] = _store_definition(attributes_class, outputs, map, map_present, map_bool, tags, labels)

          define_method(tf_type) do |name, attributes = {}|
            meta_args = {}
            resource_attrs = attributes
            if attributes.is_a?(Hash)
              meta_keys = %i[lifecycle depends_on count for_each provider provisioner]
              meta_args = attributes.select { |k, _| meta_keys.include?(k.to_sym) }
              resource_attrs = attributes.reject { |k, _| meta_keys.include?(k.to_sym) }

              # Unknown key detection runs on ALL keys (including ref-carrying ones)
              known = attributes_class.schema.map { |k| k.name }.to_set
              unknown = resource_attrs.keys.map(&:to_sym) - known.to_a
              unless unknown.empty?
                raise ArgumentError,
                  "#{tf_type}: unknown attributes #{unknown.inspect}. " \
                  "Valid attributes: #{known.to_a.sort.inspect}. " \
                  "Typo? Check Terraform docs for the correct attribute name."
              end
            end

            # Partition into validated literals + opaque refs.
            # Types stay pure. Refs handled at serialization boundary.
            input = ResourceInput.partition(attributes_class, resource_attrs)
            _synthesize_block(:resource, tf_type, name, input, map, map_present, map_bool, tags, labels, custom_block, meta_args)
            _build_reference(tf_type.to_s, name, input, outputs)
          end
        end

        def define_data(tf_type, attributes_class:, outputs: { id: :id },
                        map: [], map_present: [], map_bool: [],
                        tags: nil, labels: nil, &custom_block)
          method_name = :"data_#{tf_type}"
          @_data_definitions ||= {}
          @_data_definitions[tf_type] = _store_definition(attributes_class, outputs, map, map_present, map_bool, tags, labels)

          define_method(method_name) do |name, attributes = {}|
            if attributes.is_a?(Hash)
              known = attributes_class.schema.map { |k| k.name }.to_set
              unknown = attributes.keys.map(&:to_sym) - known.to_a
              unless unknown.empty?
                raise ArgumentError,
                  "data.#{tf_type}: unknown attributes #{unknown.inspect}. " \
                  "Valid attributes: #{known.to_a.sort.inspect}."
              end
            end
            input = ResourceInput.partition(attributes_class, attributes)
            _synthesize_block(:data, tf_type, name, input, map, map_present, map_bool, tags, labels, custom_block)
            _build_reference("data.#{tf_type}", name, input, outputs)
          end
        end

        def resource_definitions
          @_resource_definitions || {}
        end

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

      def _synthesize_block(block_type, tf_type, name, input, map, map_present, map_bool, tags, labels, custom_block, meta_args = {})
        # `_emit` bypasses Ruby's normal method lookup and dispatches straight to
        # the synthesizer's `method_missing`. Without this, attribute names that
        # collide with Kernel/Object methods (e.g. GitHub's `fork`, `raise`,
        # `send`, `class`) would invoke the Ruby builtin instead of the
        # abstract-synthesizer's block-recording DSL.
        send(block_type, tf_type, name) do
          # input[attr] resolves refs over validated attrs transparently
          map.each { |attr| send(:method_missing, attr, input[attr]) }
          map_present.each { |attr| val = input[attr]; send(:method_missing, attr, val) if val }
          map_bool.each { |attr| val = input[attr]; send(:method_missing, attr, val) unless val.nil? }
          if tags
            tag_val = input[tags]
            send(:method_missing, tags, tag_val) if tag_val&.respond_to?(:any?) && tag_val.any?
          end
          if labels
            label_val = input[labels]
            send(:method_missing, labels, label_val) if label_val&.respond_to?(:any?) && label_val.any?
          end
          instance_exec(self, input, &custom_block) if custom_block

          meta_args.each do |meta_key, meta_val|
            if meta_val.is_a?(Hash)
              send(:method_missing, meta_key) do
                meta_val.each { |k, v| send(:method_missing, k, v) }
              end
            else
              send(:method_missing, meta_key, meta_val)
            end
          end
        end
      end

      def _build_reference(type_str, name, input, outputs)
        output_hash = outputs.each_with_object({}) do |(friendly, tf_attr), h|
          h[friendly] = "${#{type_str}.#{name}.#{tf_attr}}"
        end
        ResourceReference.new(
          type: type_str,
          name: name,
          resource_attributes: input.to_h,
          outputs: output_hash
        )
      end
    end
  end
end
