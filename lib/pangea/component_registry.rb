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

module Pangea
  module ComponentRegistry
    @components = []
    @mutex = Mutex.new

    class << self
      def register_component(component_module)
        @mutex.synchronize do
          unless @components.include?(component_module)
            @components << component_module
          end
        end
      end

      def registered_components
        @mutex.synchronize { @components.dup }
      end

      def clear!
        @mutex.synchronize { @components.clear }
      end

      def registered?(component_module)
        @mutex.synchronize { @components.include?(component_module) }
      end
    end
  end
end
