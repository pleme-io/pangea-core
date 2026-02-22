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

require 'net/http'
require 'json'
require 'timeout'

module Pangea
  module Utilities
    # IP Discovery service for finding public IP addresses
    class IpDiscovery
      # Service definitions with parsers
      SERVICES = [
        {
          name: 'ipify',
          url: 'https://api.ipify.org?format=json',
          parser: ->(body) { JSON.parse(body)['ip'] }
        },
        {
          name: 'ipinfo',
          url: 'https://ipinfo.io/ip',
          parser: ->(body) { body.strip }
        },
        {
          name: 'aws_checkip',
          url: 'https://checkip.amazonaws.com',
          parser: ->(body) { body.strip }
        },
        {
          name: 'ifconfig_me',
          url: 'https://ifconfig.me',
          parser: ->(body) { body.strip }
        }
      ].freeze
      
      IP_REGEX = /\A(?:\d{1,3}\.){3}\d{1,3}\z/.freeze
      
      attr_reader :timeout, :logger
      
      def initialize(timeout: 5, logger: nil)
        @timeout = timeout
        @logger = logger || Logger.new(STDOUT)
      end
      
      # Discover public IP address from multiple services
      def discover
        SERVICES.each do |service|
          ip = try_service(service)
          return ip if ip
        end
        
        raise DiscoveryError, "Failed to discover public IP from any service"
      end
      
      # Try a single service with timeout
      def try_service(service)
        Timeout.timeout(@timeout) do
          uri = URI(service[:url])
          response = Net::HTTP.get_response(uri)
          
          if response.is_a?(Net::HTTPSuccess)
            ip = service[:parser].call(response.body)
            
            if validate_ip_format(ip)
              @logger&.info("[IpDiscovery] Discovered public IP from #{service[:name]}: #{ip}")
              return ip
            else
              @logger&.warn("[IpDiscovery] Invalid IP format from #{service[:name]}: #{ip}")
            end
          else
            @logger&.warn("[IpDiscovery] HTTP error from #{service[:name]}: #{response.code}")
          end
        end
        
        nil
      rescue Timeout::Error
        @logger&.warn("[IpDiscovery] Timeout querying #{service[:name]}")
        nil
      rescue StandardError => e
        @logger&.warn("[IpDiscovery] Error querying #{service[:name]}: #{e.message}")
        nil
      end
      
      private
      
      # Validate IP address format
      def validate_ip_format(ip)
        return false unless ip.match?(IP_REGEX)
        
        octets = ip.split('.')
        octets.all? { |octet| octet.to_i <= 255 }
      end
    end
    
    class DiscoveryError < StandardError; end
  end
end