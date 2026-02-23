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

require_relative 'mock_resource_reference'

module Pangea
  module Testing
    # Mock synthesizer for testing when TerraformSynthesizer is not available.
    # Accepts ANY resource method call (aws_, google_, azurerm_, hcloud_, cloudflare_, etc.)
    # and records the resource in the synthesis output.
    class MockTerraformSynthesizer
      attr_reader :resources, :data_sources, :outputs

      def initialize
        @resources = {}
        @data_sources = {}
        @outputs = {}
      end

      def synthesis
        result = {}
        result['resource'] = @resources unless @resources.empty?
        result['data'] = @data_sources unless @data_sources.empty?
        result['output'] = @outputs unless @outputs.empty?
        result
      end

      def method_missing(method_name, *args, &block)
        resource_type = method_name.to_s
        resource_name = args[0].to_s
        resource_config = args[1] || {}

        @resources[resource_type] ||= {}
        @resources[resource_type][resource_name] = resource_config

        MockResourceReference.new(resource_type, resource_name, resource_config)
      end

      def respond_to_missing?(_method_name, _include_private = false)
        true
      end
    end
  end
end
