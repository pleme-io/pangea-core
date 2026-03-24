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

require_relative 'cluster_result'

module Pangea
  module Contracts
    # Result object from kubernetes_cluster() — holds all created references.
    # This is the top-level contract returned by the Architecture module.
    class ArchitectureResult
      attr_reader :name, :config, :node_pools
      attr_accessor :network, :iam

      def initialize(name, config)
        @name = name
        @config = config
        @cluster = nil
        @network = nil
        @iam = nil
        @node_pools = {}
      end

      # Cluster getter — always returns a ClusterResult wrapper
      def cluster
        @cluster
      end

      # Cluster setter — wraps raw control plane refs in ClusterResult
      def cluster=(value)
        @cluster = if value.is_a?(ClusterResult)
                     value
                   elsif value
                     ClusterResult.new(value)
                   end
      end

      def add_node_pool(pool_name, ref)
        @node_pools[pool_name.to_sym] = ref
      end

      # Access outputs from the cluster reference
      def method_missing(method_name, *args, &block)
        if cluster&.respond_to?(method_name)
          cluster.public_send(method_name, *args, &block)
        else
          super
        end
      end

      def respond_to_missing?(method_name, include_private = false)
        cluster&.respond_to?(method_name, include_private) || super
      end

      def to_h
        {
          name: name,
          backend: config.respond_to?(:backend) ? config.backend : nil,
          kubernetes_version: config.respond_to?(:kubernetes_version) ? config.kubernetes_version : nil,
          region: config.respond_to?(:region) ? config.region : nil,
          managed_kubernetes: config.respond_to?(:managed_kubernetes?) ? config.managed_kubernetes? : nil,
          cluster: cluster&.to_h,
          network: network_to_h,
          iam: iam_to_h,
          node_pools: node_pools.transform_values { |np| np.respond_to?(:to_h) ? np.to_h : np }
        }
      end

      private

      def network_to_h
        return nil unless network

        if network.respond_to?(:to_h)
          result = network.to_h
          result.is_a?(Hash) ? result.transform_values { |v| v.respond_to?(:to_h) ? v.to_h : v } : result
        else
          network
        end
      end

      def iam_to_h
        return nil unless iam

        if iam.respond_to?(:to_h)
          result = iam.to_h
          result.is_a?(Hash) ? result.transform_values { |v| v.respond_to?(:to_h) ? v.to_h : v } : result
        else
          iam
        end
      end
    end
  end
end
