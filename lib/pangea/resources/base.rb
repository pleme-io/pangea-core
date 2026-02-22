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


require 'pangea/resources/types'

module Pangea
  module Resources
    # Base functionality for all resource abstractions
    module Base
      # Resource definition that gets passed to terraform-synthesizer
      class ResourceDefinition
        attr_reader :type, :name, :attributes
        
        def initialize(type, name, attributes)
          @type = type
          @name = name
          @attributes = attributes
        end
        
        # Convert to terraform-synthesizer resource block
        def to_terraform_resource(&block)
          resource(type, name, &block)
        end
      end
      
      protected
      
      # Helper method to create resource definitions
      def create_resource(type, name, attributes_class, attributes = {})
        # Validate attributes with dry-struct
        validated_attrs = attributes_class.new(attributes)
        
        # Create resource definition
        ResourceDefinition.new(type, name, validated_attrs)
      end
      
      # Helper to convert hash keys to terraform-synthesizer method calls
      def apply_attributes_to_resource(resource_block, attributes)
        attributes.each do |key, value|
          case value
          when Hash
            resource_block.public_send(key) do
              apply_attributes_to_resource(self, value)
            end
          when Array
            value.each do |item|
              if item.is_a?(Hash)
                resource_block.public_send(key) do
                  apply_attributes_to_resource(self, item)
                end
              else
                resource_block.public_send(key, item)
              end
            end
          else
            resource_block.public_send(key, value)
          end
        end
      end
      
      # Helper for reference generation
      def resource_ref(type, name, attribute)
        # This would integrate with terraform-synthesizer's ref functionality
        "${#{type}.#{name}.#{attribute}}"
      end
    end
  end
end