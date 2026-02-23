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

require 'ipaddr'

module Pangea
  module Types
    module BaseTypes
      def self.register_all(registry)
        # CIDR Block Type
        registry.register :cidr_block, String do
          format /\A\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}\/\d{1,2}\z/
          validation { |v| IPAddr.new(v) rescue false }
        end

        # Port Type
        registry.register :port, Integer do
          range 1, 65535
        end

        # Protocol Type
        registry.register :protocol, String do
          enum %w[tcp udp icmp all]
        end

        # IP Address Type
        registry.register :ip_address, String do
          format /\A\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}\z/
          validation { |v| IPAddr.new(v) rescue false }
        end

        # Domain Name Type
        registry.register :domain_name, String do
          format /\A[a-z0-9]([a-z0-9\-]{0,61}[a-z0-9])?(\.[a-z0-9]([a-z0-9\-]{0,61}[a-z0-9])?)*\z/i
          max_length 253
        end
      end
    end
  end
end
