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
    # Base typed result object for the IAM phase.
    # Provides named accessors for the core IAM outputs that all providers share.
    #
    # Provider-specific subclasses (e.g., AWS::IamResult) can add fields
    # like :log_group, :ecr_policy, :karpenter_role via inheritance.
    class IamResult
      attr_accessor :role, :instance_profile, :policies

      def initialize
        @role = nil
        @instance_profile = nil
        @policies = {}
      end

      # Hash-style access for backward compatibility
      def [](key)
        case key.to_sym
        when :role then role
        when :instance_profile then instance_profile
        when :policies then policies
        else
          # Check policies hash for named policy access
          policies[key.to_sym]
        end
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

      def to_h
        hash = {}
        hash[:role] = role if role
        hash[:instance_profile] = instance_profile if instance_profile
        policies.each { |k, v| hash[k] = v } unless policies.empty?
        hash
      end

      # Validate the contract — no required fields for base IAM
      # (some providers have empty IAM).
      def validate!
        # No required fields
      end
    end
  end
end
