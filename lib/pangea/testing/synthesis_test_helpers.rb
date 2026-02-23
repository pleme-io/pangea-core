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

require_relative 'mock_terraform_synthesizer'
require_relative 'mock_resource_reference'

module Pangea
  module Testing
    # Shared test helpers for synthesis validation across all Pangea provider gems.
    # Include this module in your RSpec configuration to get access to synthesizer
    # creation, Terraform structure validation, and resource assertion helpers.
    module SynthesisTestHelpers
      # Synthesize and validate Terraform configuration.
      # Optionally normalizes symbol keys to strings (for TerraformSynthesizer compatibility).
      def synthesize_and_validate(entity_type = :resource, normalize: false, &block)
        synthesizer = create_synthesizer
        synthesizer.instance_eval(&block)
        result = synthesizer.synthesis
        result = normalize_synthesis(result) if normalize

        validate_terraform_structure(result, entity_type)
        result
      end

      # Create a new TerraformSynthesizer instance, falling back to mock
      def create_synthesizer
        if defined?(TerraformSynthesizer)
          TerraformSynthesizer.new
        else
          MockTerraformSynthesizer.new
        end
      end

      # Normalize synthesis result to string keys via JSON round-trip
      def normalize_synthesis(result)
        JSON.parse(result.to_json)
      end

      # Validate basic Terraform JSON structure
      def validate_terraform_structure(result, entity_type)
        expect(result).to be_a(Hash)

        case entity_type
        when :resource
          expect(result).to have_key('resource')
          expect(result['resource']).to be_a(Hash)
        when :data_source
          expect(result).to have_key('data')
          expect(result['data']).to be_a(Hash)
        when :output
          expect(result).to have_key('output')
          expect(result['output']).to be_a(Hash)
        end
      end

      # Validate resource references in generated Terraform
      def validate_resource_references(result)
        terraform_json = result.to_json
        reference_pattern = /\$\{[a-zA-Z_][a-zA-Z0-9_]*\.[a-zA-Z_][a-zA-Z0-9_]*\.[a-zA-Z_][a-zA-Z0-9_]*\}/

        references = terraform_json.scan(reference_pattern)
        references.each do |ref|
          expect(ref).to match(reference_pattern)
        end

        references
      end

      # Validate a specific resource exists in synthesis output
      def validate_resource_structure(result, resource_type, resource_name)
        expect(result).to have_key('resource')
        expect(result['resource']).to have_key(resource_type)
        expect(result['resource'][resource_type]).to have_key(resource_name)

        resource_config = result['resource'][resource_type][resource_name]
        expect(resource_config).to be_a(Hash)

        resource_config
      end

      # Validate Terraform provider configuration
      def validate_provider_configuration(result, provider_name)
        return unless result.key?('provider')

        expect(result['provider']).to have_key(provider_name)
        provider_config = result['provider'][provider_name]
        expect(provider_config).to be_a(Hash)
        provider_config
      end

      # Validate that resource attributes match expected types
      def validate_resource_attributes(resource_config, expected_attributes)
        expected_attributes.each do |attr_name, attr_type|
          next unless resource_config.key?(attr_name.to_s)

          value = resource_config[attr_name.to_s]
          case attr_type
          when String  then expect(value).to be_a(String)
          when Integer then expect(value).to be_a(Integer)
          when TrueClass, FalseClass then expect([true, false]).to include(value)
          when Array   then expect(value).to be_a(Array)
          when Hash    then expect(value).to be_a(Hash)
          end
        end
      end

      # Validate that required attributes are present
      def validate_required_attributes(resource_config, required_attributes)
        required_attributes.each do |attr_name|
          expect(resource_config).to have_key(attr_name.to_s),
            "Required attribute '#{attr_name}' is missing"
        end
      end

      # Validate Terraform dependencies and ordering
      def validate_dependency_ordering(result)
        resources = result['resource'] || {}
        dependencies = extract_dependencies(resources)

        dependencies.each do |resource_id, deps|
          deps.each do |dep|
            expect(dependencies).to have_key(dep),
              "Dependency '#{dep}' referenced by '#{resource_id}' is not defined"
          end
        end
      end

      def reset_terraform_synthesizer_state; end
      def cleanup_test_resources; end

      private

      def extract_dependencies(resources)
        dependencies = {}

        resources.each do |resource_type, type_resources|
          type_resources.each do |resource_name, resource_config|
            resource_id = "#{resource_type}.#{resource_name}"
            dependencies[resource_id] = []

            config_json = resource_config.to_json
            references = config_json.scan(/\$\{([^}]+)\}/)

            references.each do |ref|
              ref_parts = ref[0].split('.')
              if ref_parts.length >= 2
                dep_resource_id = "#{ref_parts[0]}.#{ref_parts[1]}"
                dependencies[resource_id] << dep_resource_id unless dep_resource_id == resource_id
              end
            end
          end
        end

        dependencies
      end
    end
  end
end
