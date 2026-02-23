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
      module NetworkValidators
        def valid_cidr!(value)
          unless value.match?(%r{\A\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}/\d{1,2}\z})
            raise ValidationError, "Invalid CIDR format: #{value}"
          end

          ip, prefix = value.split('/')
          octets = ip.split('.').map(&:to_i)
          prefix_int = prefix.to_i

          unless octets.all? { |o| (0..255).include?(o) }
            raise ValidationError, "Invalid IP address in CIDR: #{value}"
          end

          unless (0..32).include?(prefix_int)
            raise ValidationError, "Invalid prefix length (0-32): #{value}"
          end

          value
        end

        def valid_port!(value)
          unless value.is_a?(Integer) && (0..65535).include?(value)
            raise ValidationError, "Port must be 0-65535, got: #{value}"
          end
          value
        end

        def valid_port_range!(from_port, to_port)
          valid_port!(from_port)
          valid_port!(to_port)
          if from_port > to_port
            raise ValidationError, "from_port (#{from_port}) cannot exceed to_port (#{to_port})"
          end
          true
        end

        def valid_domain!(value, allow_wildcard: false)
          pattern = if allow_wildcard
                      /\A(\*\.)?(?:[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\.)*[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\z/i
                    else
                      /\A(?:[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\.)*[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\z/i
                    end

          unless value.match?(pattern)
            raise ValidationError, "Invalid domain name: #{value}"
          end
          value
        end

        def valid_email!(value)
          unless value.match?(/\A[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}\z/)
            raise ValidationError, "Invalid email format: #{value}"
          end
          value
        end
      end
    end
  end
end
