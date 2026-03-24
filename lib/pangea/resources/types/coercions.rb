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

require_relative 'core'

module Pangea
  module Resources
    module Types
      # Port as String — accepts Integer, coerces to String.
      # Use for AWS health_check.port, listener.port etc. where the API
      # expects a string but callers naturally pass integers.
      PortString = Coercible::String

      # Port as Integer — accepts String, coerces to Integer.
      # Constrained to valid port range 0-65535.
      PortInt = Coercible::Integer.constrained(gteq: 0, lteq: 65535)

      # Boolean — accepts String 'true'/'false', Integer 0/1, coerces to Bool.
      # Handles common type mismatches from YAML configs, CLI args, and API
      # responses where booleans arrive as strings or integers.
      CoercibleBool = Bool.constructor do |v|
        case v
        when ::String then %w[true 1 yes].include?(v.downcase)
        when ::Integer then v != 0
        else !!v
        end
      end
    end
  end
end
