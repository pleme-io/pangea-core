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
  module Testing
    # Mock resource reference for testing. Returns Terraform-style interpolation
    # strings for attribute access (e.g., "${aws_vpc.main.id}").
    class MockResourceReference
      attr_reader :type, :name, :attributes

      def initialize(type, name, attributes = {})
        @type = type
        @name = name
        @attributes = attributes
      end

      def id
        "${#{@type}.#{@name}.id}"
      end

      def arn
        "${#{@type}.#{@name}.arn}"
      end

      def email
        "${#{@type}.#{@name}.email}"
      end

      def endpoint
        "${#{@type}.#{@name}.endpoint}"
      end

      def ipv4_address
        "${#{@type}.#{@name}.ipv4_address}"
      end

      def to_h
        { type: @type, name: @name, attributes: @attributes }
      end

      def method_missing(method_name, *_args, &_block)
        # Check both string and symbol key access
        if @attributes.key?(method_name)
          @attributes[method_name]
        elsif @attributes.key?(method_name.to_s)
          @attributes[method_name.to_s]
        else
          "${#{@type}.#{@name}.#{method_name}}"
        end
      end

      def respond_to_missing?(_method_name, _include_private = false)
        true
      end
    end
  end
end
