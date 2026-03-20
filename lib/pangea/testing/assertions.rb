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

module Pangea
  module Testing
    module Assertions
      def assert_terraform_structure(result, resource_type, resource_name)
        expect(result).to be_a(Hash)
        resource_key = result.key?('resource') ? 'resource' : :resource
        resources = result[resource_key]
        expect(resources).to be_a(Hash)
        type_resources = resources[resource_type] || resources[resource_type.to_sym]
        expect(type_resources).to be_a(Hash)
        config = type_resources[resource_name] || type_resources[resource_name.to_sym]
        expect(config).to be_a(Hash)
        config
      end

      def assert_resource_reference(ref, expected_type, expected_name, expected_outputs = {})
        expect(ref).to be_a(Pangea::Resources::ResourceReference)
        expect(ref.type).to eq(expected_type)
        expect(ref.name).to eq(expected_name)
        expected_outputs.each do |key, value|
          expect(ref.outputs[key]).to eq(value)
        end
        ref
      end

      def assert_tags_present(config, expected_tags)
        tags = config['tags'] || config[:tags]
        expect(tags).not_to be_nil
        expected_tags.each do |key, value|
          expect(tags[key.to_s] || tags[key.to_sym]).to eq(value)
        end
      end
    end
  end
end
