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

require 'pangea/utilities/ip_discovery'
require 'pangea/resource_registry'

module Pangea
  module Resources
    # Network helpers for templates
    module NetworkHelpers
      # Discover public IP address - available in template context
      def discover_public_ip(timeout: 5)
        # Cache the IP discovery result to avoid multiple calls
        @_discovered_ip ||= begin
          discovery = Utilities::IpDiscovery.new(timeout: timeout)
          ip = discovery.discover
          puts "[Pangea] Discovered public IP: #{ip}"
          ip
        end
      end
      
      # Create CIDR block from IP and mask
      def cidr_block(ip, mask)
        "#{ip}/#{mask}"
      end
      
      # Calculate subnet CIDR from base and offset
      def subnet_cidr(base_cidr, subnet_bits, index)
        base_ip, base_mask = base_cidr.split('/')
        octets = base_ip.split('.').map(&:to_i)
        
        # Calculate new IP based on subnet bits and index
        subnet_size = 2 ** subnet_bits
        offset = index * subnet_size
        
        # Apply offset to appropriate octet
        octet_index = (32 - base_mask.to_i - subnet_bits) / 8
        octets[octet_index] += offset
        
        new_ip = octets.join('.')
        new_mask = base_mask.to_i + subnet_bits
        
        "#{new_ip}/#{new_mask}"
      end
      
      # Generate availability zones for a region
      def availability_zones(region, count = 3)
        zones = ('a'..'f').to_a
        zones.take(count).map { |zone| "#{region}#{zone}" }
      end
      
      # Validate IP address format
      def valid_ip?(ip)
        return false unless ip =~ /\A(?:\d{1,3}\.){3}\d{1,3}\z/
        
        ip.split('.').all? { |octet| octet.to_i <= 255 }
      end
    end
  end
end

# Auto-register the module when loaded
Pangea::ResourceRegistry.register_module(Pangea::Resources::NetworkHelpers)