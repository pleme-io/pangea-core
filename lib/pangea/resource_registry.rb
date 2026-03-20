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
  # Global registry for resource modules that auto-register when loaded.
  # Thread-safe: all mutation and read paths are guarded by a Mutex.
  module ResourceRegistry
    @registered_modules = Set.new
    @provider_modules = Hash.new { |h, k| h[k] = Set.new }
    @mutex = Mutex.new

    class << self
      # Register a module to be available in template contexts
      def register_module(mod)
        @mutex.synchronize { @registered_modules.add(mod) }
      end

      # Get all registered modules
      def registered_modules
        @mutex.synchronize { @registered_modules.to_a }
      end

      # Clear registry (useful for testing)
      def clear!
        @mutex.synchronize do
          @registered_modules.clear
          @provider_modules.clear
        end
      end

      # Check if a module is registered
      def registered?(mod)
        @mutex.synchronize { @registered_modules.include?(mod) }
      end

      # Support provider-based registration used by individual resources
      def register(provider, mod)
        @mutex.synchronize do
          @provider_modules[provider].add(mod)
          # Also add to global registry for backward compatibility
          @registered_modules.add(mod)
        end
      end

      # Get modules for a specific provider
      def modules_for(provider)
        @mutex.synchronize { @provider_modules[provider].to_a }
      end

      # Get registry statistics
      def stats
        @mutex.synchronize do
          {
            total_modules: @registered_modules.size,
            modules: @registered_modules.map(&:name),
            by_provider: @provider_modules.transform_values(&:size)
          }
        end
      end
    end
  end
end