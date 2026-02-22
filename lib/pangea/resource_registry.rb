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


require 'set'

module Pangea
  # Global registry for resource modules that auto-register when loaded
  module ResourceRegistry
    @registered_modules = Set.new
    @provider_modules = Hash.new { |h, k| h[k] = Set.new }

    class << self
      # Register a module to be available in template contexts
      def register_module(mod)
        @registered_modules.add(mod)
      end

      # Get all registered modules
      def registered_modules
        @registered_modules.to_a
      end

      # Clear registry (useful for testing)
      def clear!
        @registered_modules.clear
      end

      # Check if a module is registered
      def registered?(mod)
        @registered_modules.include?(mod)
      end

      # Support provider-based registration used by individual resources
      def register(provider, mod)
        @provider_modules[provider].add(mod)
        # Also add to global registry for backward compatibility
        @registered_modules.add(mod)
      end
      
      # Get modules for a specific provider
      def modules_for(provider)
        @provider_modules[provider].to_a
      end

      # Get registry statistics
      def stats
        {
          total_modules: @registered_modules.size,
          modules: @registered_modules.map(&:name),
          by_provider: @provider_modules.transform_values(&:size)
        }
      end
    end
  end
end