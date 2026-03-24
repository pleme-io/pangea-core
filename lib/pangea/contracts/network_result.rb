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

require_relative 'errors'

module Pangea
  module Contracts
    # Base typed result object for the network phase.
    # Provides named accessors instead of raw hash access, ensuring backends
    # and templates agree on the contract.
    #
    # Provider-specific subclasses (e.g., AWS::NetworkResult) can add fields
    # like :igw, :route_table, :etcd_bucket via inheritance.
    class NetworkResult
      attr_accessor :vpc, :sg

      def initialize
        @vpc = nil
        @sg = nil
        @subnets = []
      end

      # Add a subnet to the ordered list
      def add_subnet(name, ref)
        @subnets << { name: name, ref: ref }
      end

      # All subnets as an array of resource references
      def subnets
        @subnets.map { |s| s[:ref] }
      end

      # Alias used by templates (e.g., akeyless_dev_cluster.rb)
      alias public_subnets subnets

      # Subnet IDs as an array of strings (terraform refs)
      def subnet_ids
        subnets.map(&:id)
      end

      # Hash-style access for backward compatibility with existing code
      # that uses result.network[:vpc], result.network[:sg], etc.
      def [](key)
        case key.to_sym
        when :vpc then vpc
        when :sg then sg
        when :public_subnets then public_subnets
        when :subnet_ids then subnet_ids
        when :subnets then subnets
        else
          # Support :subnet_a, :subnet_b legacy keys
          match = @subnets.find { |s| s[:name] == key.to_sym }
          match&.dig(:ref)
        end
      end

      # Hash-like iteration for backward compatibility (e.g., resolve_subnet_ids
      # in aws_nixos.rb uses .select { |k, _| k.to_s.start_with?('subnet_') })
      def select(&block)
        to_h.select(&block)
      end

      def to_h
        hash = {}
        hash[:vpc] = vpc if vpc
        hash[:sg] = sg if sg
        @subnets.each { |s| hash[s[:name]] = s[:ref] }
        hash
      end

      def dig(*keys)
        to_h.dig(*keys)
      end

      # Hash-like key checks for backward compatibility with RSpec have_key matcher
      def key?(key)
        !self[key].nil?
      end
      alias has_key? key?
      alias include? key?

      # Validate the contract — vpc is required for a valid network result.
      # Raises ContractError if the contract is violated.
      def validate!
        raise ContractError, 'NetworkResult requires a vpc reference' if vpc.nil?
      end
    end
  end
end
