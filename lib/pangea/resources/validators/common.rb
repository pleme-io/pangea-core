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
  module Resources
    module Validators
      module Common
        def check_mutually_exclusive(attrs, *field_names)
          present = field_names.select { |f| !attrs.public_send(f).nil? }
          if present.length > 1
            raise Dry::Struct::Error, "Cannot specify both '#{present.join("' and '")}'"
          end
        end

        def check_required_one_of(attrs, *field_names)
          present = field_names.select { |f| !attrs.public_send(f).nil? }
          if present.empty?
            raise Dry::Struct::Error, "Must specify one of: #{field_names.join(', ')}"
          end
        end

        def skip_validation_for_refs?(attrs, *field_names)
          field_names.any? { |f| Pangea::Resources::BaseAttributes.terraform_reference?(attrs.public_send(f).to_s) }
        end
      end
    end
  end
end
