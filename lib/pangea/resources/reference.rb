# frozen_string_literal: true

# Copyright 2025 The Pangea Authors
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

require 'dry-struct'
require 'pangea/resources/types'

module Pangea
  module Resources
    # Base computed attributes - common to all resources
    class BaseComputedAttributes
      attr_reader :resource_ref

      def initialize(resource_ref)
        @resource_ref = resource_ref
      end

      # Common terraform attributes available on all resources
      def id
        resource_ref.ref(:id)
      end

      def terraform_resource_name
        "#{resource_ref.type}.#{resource_ref.name}"
      end

      def tags
        resource_ref.resource_attributes[:tags] || {}
      end
    end

    # Resource reference object returned by resource functions
    # Provides access to resource attributes, outputs, and computed properties
    class ResourceReference < Dry::Struct
      # Registry for provider-specific computed attributes classes
      @@computed_attributes_registry = {}

      # Normalize input keys: accept `attributes:` as alias for `resource_attributes:`
      transform_keys do |key|
        k = key.to_sym
        k == :attributes ? :resource_attributes : k
      end

      attribute :type, Types::Coercible::String  # aws_vpc, aws_subnet, etc. (coerces Symbol → String)
      attribute :name, Types::Symbol | Types::String  # Resource name
      # Accept Hash or Dry::Struct (auto-coerced via constructor)
      attribute :resource_attributes, Types::Hash.constructor { |v|
        v.respond_to?(:to_h) && !v.is_a?(Hash) ? v.to_h : v
      }
      attribute :outputs, Types::Hash.default({}.freeze)  # Available outputs for this resource type
      attribute? :computed_properties, Types::Hash.optional  # Resource-specific computed properties
      attribute? :computed, Types::Hash.optional             # Alias for computed_properties

      # Register computed attributes classes for resource types
      # @param mapping [Hash] resource_type => computed_attributes_class
      def self.register_computed_attributes(mapping)
        @@computed_attributes_registry.merge!(mapping)
      end

      # Alias for `type` — some callers prefer `resource_type` to avoid conflicts
      def resource_type
        type.to_sym
      end

      # Generate terraform reference for any attribute
      def ref(attribute_name)
        "${#{type}.#{name}.#{attribute_name}}"
      end

      # Alias for ref - more natural syntax
      def [](attribute_name)
        ref(attribute_name)
      end

      # Access to common outputs with friendly names
      def id
        ref(:id)
      end

      def arn
        ref(:arn)
      end

      # Resource-specific computed properties (extensible via register_computed_attributes)
      def computed_attributes
        @computed_attributes ||= begin
          klass = @@computed_attributes_registry[type]
          klass ? klass.new(self) : BaseComputedAttributes.new(self)
        end
      end

      # Method delegation to outputs, computed properties, and computed attributes
      def method_missing(method_name, *args, &block)
        if outputs.key?(method_name)
          outputs[method_name]
        elsif computed_properties&.key?(method_name)
          computed_properties[method_name]
        elsif computed&.key?(method_name)
          computed[method_name]
        elsif computed_attributes.respond_to?(method_name)
          computed_attributes.public_send(method_name, *args, &block)
        else
          super
        end
      end

      def respond_to_missing?(method_name, include_private = false)
        outputs.key?(method_name) ||
          computed_properties&.key?(method_name) ||
          computed&.key?(method_name) ||
          computed_attributes.respond_to?(method_name, include_private) ||
          super
      end

      # Convert to hash for terraform-synthesizer integration
      def to_h
        {
          type: type,
          name: name,
          attributes: resource_attributes,  # Use 'attributes' as key for compatibility
          outputs: outputs
        }
      end
    end
  end
end
