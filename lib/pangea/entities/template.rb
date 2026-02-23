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
    class Template < Dry::Struct
      attribute :name, Pangea::Types::Identifier
      attribute :content, Pangea::Types::Strict::String
      attribute :file_path, Pangea::Types::FilePath.optional.default(nil)

      attribute :namespace, Pangea::Types::NamespaceString.optional.default(nil)
      attribute :project, Pangea::Types::ProjectString.optional.default(nil)
      attribute :variables, Pangea::Types::SymbolizedHash.default({}.freeze)

      attribute :target_version, Pangea::Types::TerraformVersion.optional.default(nil)
      attribute :strict_mode, Pangea::Types::Strict::Bool.default(false)

      def source
        file_path || "<inline:#{name}>"
      end

      def from_file?
        !file_path.nil?
      end

      def cache_key
        parts = [namespace, project, name].compact
        parts.join('/')
      end

      def validate!
        errors = []

        if content.strip.empty?
          errors << "Template content cannot be empty"
        end

        if content.include?("<%") || content.include?("{{")
          errors << "Template appears to contain ERB or Mustache syntax (not supported)"
        end

        raise ValidationError, errors.join(", ") unless errors.empty?
        true
      end

      def metadata
        return {} unless content.start_with?("# @")

        metadata = {}
        content.lines.each do |line|
          break unless line.start_with?("# @")

          if line =~ /# @(\w+):\s*(.+)$/
            key = $1.to_sym
            value = $2.strip
            metadata[key] = value
          end
        end

        metadata
      end

      def content_without_metadata
        return content unless content.start_with?("# @")

        lines = content.lines
        lines.drop_while { |line| line.start_with?("# @") }.join
      end
    end

    class CompilationResult < Dry::Struct
      attribute :success, Pangea::Types::Strict::Bool
      attribute :terraform_json, Pangea::Types::Strict::String.optional.default(nil)
      attribute :errors, Pangea::Types::StringArray.default([].freeze)
      attribute :warnings, Pangea::Types::StringArray.default([].freeze)
      attribute :template_name, Pangea::Types::Strict::String.optional.default(nil)
      attribute :template_count, Pangea::Types::Strict::Integer.optional.default(nil)

      def success?
        success && errors.empty?
      end

      def failure?
        !success?
      end
    end
  end
end
