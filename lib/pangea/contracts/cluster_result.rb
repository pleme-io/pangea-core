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

require_relative 'security_group_accessor'

module Pangea
  module Contracts
    # Base typed result object for the cluster phase.
    # Wraps the backend-specific control plane reference and provides
    # named accessors for common cluster outputs.
    #
    # Unknown methods are delegated to control_plane_ref for backward
    # compatibility with provider-specific attributes.
    class ClusterResult
      attr_reader :control_plane_ref

      def initialize(control_plane_ref)
        @control_plane_ref = control_plane_ref
      end

      # Named accessors for common cluster components
      def nlb
        control_plane_ref.nlb
      end

      def asg
        control_plane_ref.asg
      end

      def launch_template
        control_plane_ref.lt
      end
      alias lt launch_template

      def target_group
        control_plane_ref.tg
      end
      alias tg target_group

      def listener
        control_plane_ref.listener
      end

      # Security group ID — the SG used for cluster nodes
      def sg_id
        control_plane_ref.sg_id
      end

      # Convenience: return a pseudo-reference for security_group access
      # Templates use result.cluster.security_group.id
      def security_group
        SecurityGroupAccessor.new(control_plane_ref.sg_id)
      end

      def id
        control_plane_ref.id
      end

      def arn
        control_plane_ref.arn
      end

      def to_h
        control_plane_ref.respond_to?(:to_h) ? control_plane_ref.to_h : {}
      end

      # Forward unknown methods to control_plane_ref for backward compatibility
      def method_missing(method_name, *args, &block)
        if control_plane_ref.respond_to?(method_name)
          control_plane_ref.public_send(method_name, *args, &block)
        else
          super
        end
      end

      def respond_to_missing?(method_name, include_private = false)
        control_plane_ref.respond_to?(method_name, include_private) || super
      end
    end
  end
end
