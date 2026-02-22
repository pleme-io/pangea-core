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
require 'dry-types'
require 'json'
require 'base64'

module Pangea
  module Resources
    # Common types for resource definitions
    module Types
      include Dry.Types()

      # Provider type registries — provider gems register their Types module here
      # so T::SomeProviderType resolves to AWS::Types::SomeProviderType etc.
      @provider_type_modules = []

      def self.register_provider_types(mod)
        @provider_type_modules << mod unless @provider_type_modules.include?(mod)
      end

      def self.const_missing(name)
        if name == :ResourceReference
          require 'pangea/resources/reference' unless defined?(::Pangea::Resources::ResourceReference)
          return ::Pangea::Resources::ResourceReference
        end

        # Search registered provider type modules
        @provider_type_modules.each do |mod|
          return mod.const_get(name) if mod.const_defined?(name, false)
        end

        super
      end

      # Provider-agnostic shared types

      # CIDR block validation (e.g., "10.0.0.0/16")
      CidrBlock = String.constrained(format: /\A\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}\/\d{1,2}\z/)

      # Domain name validation
      DomainName = String.constrained(
        format: /\A(?:[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\.)*[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\z/i
      )

      # Wildcard domain name validation
      WildcardDomainName = String.constrained(
        format: /\A\*\.(?:[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\.)*[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\z/i
      )

      # Email address validation
      EmailAddress = String.constrained(format: /\A[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}\z/)

      # Network port (0-65535)
      Port = Integer.constrained(gteq: 0, lteq: 65535)

      # Network protocols
      IpProtocol = String.enum('tcp', 'udp', 'icmp', 'icmpv6', 'all', '-1')

      # Port range
      PortRange = Hash.schema(from_port: Port, to_port: Port)

      # POSIX permissions (octal format)
      PosixPermissions = String.constrained(format: /\A[0-7]{3,4}\z/)

      # Unix User/Group IDs
      UnixUserId = Integer.constrained(gteq: 0, lteq: 4294967295)
      UnixGroupId = Integer.constrained(gteq: 0, lteq: 4294967295)
    end
  end
end
