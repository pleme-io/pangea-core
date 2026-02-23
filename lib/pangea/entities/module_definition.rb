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

module Pangea
  module Entities
    class ModuleDefinition < Dry::Struct
      module Type
        RESOURCE = :resource
        FUNCTION = :function
        COMPOSITE = :composite
      end

      attribute :name, Pangea::Types::ModuleName
      attribute :version, Pangea::Types::Version.optional.default("0.0.1")
      attribute :description, Pangea::Types::OptionalString.default(nil)
      attribute :author, Pangea::Types::OptionalString.default(nil)

      attribute :type, Pangea::Types::Strict::Symbol.default(:resource).enum(:resource, :function, :composite)
      attribute :source, Pangea::Types::FilePath.optional.default(nil)
      attribute :path, Pangea::Types::DirectoryPath.optional.default(nil)

      attribute :inputs, Pangea::Types::SymbolizedHash.default({}.freeze)
      attribute :outputs, Pangea::Types::SymbolizedHash.default({}.freeze)
      attribute :dependencies, Pangea::Types::ModuleArray.default([].freeze)

      attribute :ruby_version, Pangea::Types::Version.optional.default(nil)
      attribute :required_gems, Pangea::Types::SymbolizedHash.default({}.freeze)

      def resource_module?
        type == Type::RESOURCE || type == Type::COMPOSITE
      end

      def function_module?
        type == Type::FUNCTION || type == Type::COMPOSITE
      end

      def load_path
        return path if path
        return File.dirname(source) if source

        "modules/#{name}"
      end

      def required_inputs
        inputs.select { |_, config| config[:required] }.keys
      end

      def optional_inputs
        inputs.reject { |_, config| config[:required] }.keys
      end

      def validate_inputs(provided_inputs)
        errors = []
        provided = provided_inputs.keys.map(&:to_sym)

        required_inputs.each do |input|
          unless provided.include?(input)
            errors << "Missing required input: #{input}"
          end
        end

        provided.each do |input|
          unless inputs.key?(input)
            errors << "Unknown input: #{input}"
          end
        end

        provided_inputs.each do |key, value|
          if inputs[key.to_sym] && inputs[key.to_sym][:type]
            expected_type = inputs[key.to_sym][:type]
          end
        end

        raise ValidationError, errors.join(", ") unless errors.empty?
        true
      end

      def to_documentation
        doc = ["# Module: #{name}"]
        doc << "Version: #{version}" if version
        doc << "\n#{description}" if description
        doc << "\nAuthor: #{author}" if author

        if inputs.any?
          doc << "\n## Inputs"
          inputs.each do |name, config|
            required = config[:required] ? " (required)" : ""
            doc << "- `#{name}`#{required}: #{config[:description] || 'No description'}"
            doc << "  - Type: #{config[:type]}" if config[:type]
            doc << "  - Default: #{config[:default]}" if config[:default]
          end
        end

        if outputs.any?
          doc << "\n## Outputs"
          outputs.each do |name, config|
            doc << "- `#{name}`: #{config[:description] || 'No description'}"
          end
        end

        doc.join("\n")
      end
    end
  end
end
