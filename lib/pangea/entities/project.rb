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
    class Project < Dry::Struct
      attribute :name, Pangea::Types::ProjectString
      attribute :namespace, Pangea::Types::NamespaceString
      attribute :site, Pangea::Types::SiteString.optional.default(nil)
      attribute :description, Pangea::Types::OptionalString.default(nil)

      attribute :modules, Pangea::Types::ModuleArray.default([].freeze)
      attribute :variables, Pangea::Types::SymbolizedHash.default({}.freeze)
      attribute :outputs, Pangea::Types::StringArray.default([].freeze)
      attribute :depends_on, Pangea::Types::IdentifierArray.default([].freeze)

      attribute :terraform_version, Pangea::Types::TerraformVersion.optional.default(nil)
      attribute :tags, Pangea::Types::SymbolizedHash.default({}.freeze)

      def full_name
        [namespace, site, name].compact.join('.')
      end

      def state_key
        parts = [namespace]
        parts << site if site
        parts << name
        parts.join('/')
      end

      def has_modules?
        !modules.empty?
      end

      def has_dependencies?
        !depends_on.empty?
      end

      def module_config(module_name)
        modules.find { |m| m == module_name }
      end

      def to_backend_config(prefix: nil)
        key_parts = [prefix, state_key].compact
        {
          key: key_parts.join('/'),
          workspace_key_prefix: "workspaces"
        }
      end

      def validate!
        errors = []

        if depends_on.include?(name)
          errors << "Project cannot depend on itself"
        end

        modules.each do |mod|
          unless mod.match?(/\A[a-z][a-z0-9_-]*\z/)
            errors << "Invalid module name: #{mod}"
          end
        end

        raise ValidationError, errors.join(", ") unless errors.empty?
        true
      end
    end
  end
end
