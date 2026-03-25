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
        @subnets = { public: [], web: [], data: [] }
      end

      # ── Tiered Subnet Management ──────────────────────────────────
      # Three tiers: public (NLBs, bastions), web (K8s nodes), data (databases)
      # Each tier has its own subnets, route table, and routing.

      # Add a subnet to a specific tier.
      # @param name [Symbol] unique name (e.g., :public_a, :web_a, :data_b)
      # @param ref [ResourceReference] the subnet resource reference
      # @param tier [Symbol] :public, :web, or :data (default: :public for backward compat)
      def add_subnet(name, ref, tier: :public)
        tier_sym = tier.to_sym
        @subnets[tier_sym] ||= []
        @subnets[tier_sym] << { name: name, ref: ref }
      end

      # All subnets across all tiers (backward compatible)
      def subnets
        @subnets.values.flatten.map { |s| s[:ref] }
      end

      # Public subnets only (internet-facing: NLBs, NAT gateways)
      def public_subnets
        (@subnets[:public] || []).map { |s| s[:ref] }
      end

      # Web tier subnets (K8s nodes, application workloads)
      def web_subnets
        (@subnets[:web] || []).map { |s| s[:ref] }
      end

      # Data tier subnets (databases, caches, internal services)
      def data_subnets
        (@subnets[:data] || []).map { |s| s[:ref] }
      end

      # Public subnet IDs
      def public_subnet_ids
        public_subnets.map(&:id)
      end

      # Web tier subnet IDs
      def web_subnet_ids
        web_subnets.map(&:id)
      end

      # Data tier subnet IDs
      def data_subnet_ids
        data_subnets.map(&:id)
      end

      # All subnet IDs across all tiers (backward compatible)
      def subnet_ids
        subnets.map(&:id)
      end

      # Hash-style access for backward compatibility
      def [](key)
        case key.to_sym
        when :vpc then vpc
        when :sg then sg
        when :public_subnets then public_subnets
        when :web_subnets then web_subnets
        when :data_subnets then data_subnets
        when :subnet_ids then subnet_ids
        when :public_subnet_ids then public_subnet_ids
        when :web_subnet_ids then web_subnet_ids
        when :data_subnet_ids then data_subnet_ids
        when :subnets then subnets
        else
          # Support named keys like :subnet_a, :public_a, :web_b
          all_subnets = @subnets.values.flatten
          match = all_subnets.find { |s| s[:name] == key.to_sym }
          match&.dig(:ref)
        end
      end

      def select(&block)
        to_h.select(&block)
      end

      def to_h
        hash = {}
        hash[:vpc] = vpc if vpc
        hash[:sg] = sg if sg
        @subnets.each do |tier, subs|
          subs.each { |s| hash[s[:name]] = s[:ref] }
        end
        hash
      end

      def dig(*keys)
        to_h.dig(*keys)
      end

      def key?(key)
        !self[key].nil?
      end
      alias has_key? key?
      alias include? key?

      def validate!
        raise ContractError, 'NetworkResult requires a vpc reference' if vpc.nil?
      end
    end
  end
end
