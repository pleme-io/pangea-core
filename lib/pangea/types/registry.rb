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

require 'singleton'

module Pangea
  module Types
    class Registry
      include Singleton

      def initialize
        @types = {}
      end

      def register(name, base_type, &block)
        type_def = TypeDefinition.new(name, base_type)
        type_def.instance_eval(&block) if block_given?
        @types[name] = type_def
      end

      def [](name)
        @types[name] || raise("Unknown type: #{name}")
      end

      class TypeDefinition
        attr_reader :name, :base_type, :validations, :constraints

        def initialize(name, base_type)
          @name = name
          @base_type = base_type
          @validations = []
          @constraints = {}
        end

        def format(regex)
          @constraints[:format] = regex
        end

        def enum(values)
          @constraints[:enum] = values
        end

        def range(min, max)
          @constraints[:range] = (min..max)
        end

        def max_length(length)
          @constraints[:max_length] = length
        end

        def validation(&block)
          @validations << block
        end
      end
    end
  end
end
