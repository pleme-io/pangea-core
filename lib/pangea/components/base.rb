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
  module Components
    module Base
      class ComponentError < StandardError; end
      class ValidationError < ComponentError; end
      class CompositionError < ComponentError; end

      def validate_required_attributes(attributes, required)
        missing = required - attributes.keys
        unless missing.empty?
          raise ValidationError, "Missing required attributes: #{missing.join(', ')}"
        end
      end

      def calculate_subnet_cidr(vpc_cidr, index, new_bits = 8)
        require 'ipaddr'

        vpc_network = IPAddr.new(vpc_cidr)
        vpc_prefix = vpc_cidr.split('/').last.to_i
        subnet_prefix = vpc_prefix + new_bits

        subnet_size = 2 ** (32 - subnet_prefix)
        subnet_network = vpc_network.to_i + (index * subnet_size)

        "#{IPAddr.new(subnet_network, Socket::AF_INET)}/#{subnet_prefix}"
      end

      def component_resource_name(component_name, resource_type, suffix = nil)
        parts = [component_name, resource_type]
        parts << suffix if suffix
        parts.join('_').to_sym
      end

      def merge_tags(default_tags, user_tags = {})
        default_tags.merge(user_tags)
      end

      def component_outputs(resources, computed = {})
        {
          resources: resources,
          computed: computed,
          created_at: Time.now.utc.iso8601
        }
      end
    end
  end
end
