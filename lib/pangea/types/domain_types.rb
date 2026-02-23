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

require 'dry-types'
require 'dry-struct'
require 'json'

module Pangea
  module Types
    include Dry.Types()

    # Basic types with coercion
    StrippedString = Coercible::String.constructor(&:strip)
    SymbolizedString = Coercible::Symbol
    Path = Coercible::String.constrained(min_size: 1)

    # JSON/Hash types
    JSONHash = Strict::Hash
    SymbolizedHash = Strict::Hash.constructor do |value|
      case value
      when Hash
        value.transform_keys(&:to_sym).transform_values do |v|
          if v.respond_to?(:transform_keys)
            v.transform_keys(&:to_sym)
          else
            v
          end
        end
      when String then JSON.parse(value, symbolize_names: true)
      else value
      end
    end

    # Domain-specific identifiers
    Identifier = Strict::String.constrained(
      format: /\A[a-z][a-z0-9_-]*\z/,
      min_size: 1,
      max_size: 63
    )

    NamespaceString = Identifier
    ProjectString = Identifier
    SiteString = Identifier
    ModuleName = Identifier

    # File system types
    FilePath = Strict::String.constrained(min_size: 1)
    DirectoryPath = FilePath
    FileName = Strict::String.constrained(
      format: /\A[a-zA-Z0-9._-]+\z/,
      min_size: 1
    )

    # State backend configuration
    StateBackendType = Strict::Symbol.enum(:s3, :local)

    # Terraform/OpenTofu types
    TerraformAction = Strict::Symbol.enum(:plan, :apply, :destroy, :init)
    TerraformVersion = Strict::String.constrained(
      format: /\A\d+\.\d+\.\d+\z/
    )

    # Configuration file types
    ConfigFormat = Strict::Symbol.enum(:yaml, :yml, :json, :toml, :rb)

    # Template and synthesis types
    TerraformJSON = Strict::Hash
    ResourceType = Strict::String.constrained(
      format: /\A[a-z][a-z0-9_]*\z/
    )
    ResourceName = Identifier

    # Environment variables
    EnvironmentVariable = Strict::String.constrained(
      format: /\A[A-Z][A-Z0-9_]*\z/
    )

    # Semantic versioning
    Version = Strict::String.constrained(
      format: /\A\d+\.\d+\.\d+(-[a-z0-9]+)?\z/
    )

    # URL types
    HttpUrl = Strict::String.constrained(
      format: %r{\Ahttps?://[^\s]+\z}
    )
    GitUrl = Strict::String.constrained(
      format: %r{\A(https?://|git@|git://)[^\s]+\.git\z}
    )

    # Arrays
    StringArray = Strict::Array.of(Strict::String)
    IdentifierArray = Strict::Array.of(Identifier)
    ModuleArray = Strict::Array.of(ModuleName)

    # Optional types
    OptionalString = Strict::String.optional
    OptionalIdentifier = Identifier.optional
    OptionalPath = FilePath.optional
  end
end
