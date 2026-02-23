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

require_relative 'errors'

module Pangea
  module Validation
    class Result
      attr_reader :errors, :warnings, :suggestions

      def initialize
        @errors = []
        @warnings = []
        @suggestions = []
      end

      def valid?
        @errors.empty?
      end

      def add_error(message)
        @errors << message
      end

      def add_warning(message)
        @warnings << message
      end

      def add_suggestion(message)
        @suggestions << message
      end

      def to_s
        output = []

        if errors.any?
          output << "Errors:"
          errors.each { |e| output << "  - #{e}" }
        end

        if warnings.any?
          output << "\nWarnings:"
          warnings.each { |w| output << "  - #{w}" }
        end

        if suggestions.any?
          output << "\nSuggestions:"
          suggestions.each { |s| output << "  - #{s}" }
        end

        output.join("\n")
      end
    end

    module Helpers
      def validate_name!(name)
        unless name.is_a?(Symbol) || name.is_a?(String)
          raise Errors::ValidationError.invalid_type('resource', 'name', 'Symbol or String', name.class)
        end

        unless name.to_s.match?(/\A[a-z][a-z0-9_]*\z/)
          raise Errors::ValidationError.invalid_attribute('resource', 'name', name, 'lowercase letters, numbers, and underscores')
        end
      end

      def validate_required_attributes(resource_type, attributes, required)
        result = Result.new

        required.each do |attr|
          unless attributes.key?(attr)
            result.add_error(Errors::ValidationError.missing_required(resource_type, attr))

            case attr
            when :subnet_id
              result.add_suggestion("Use ref(:subnet, :subnet_name, :id) to reference a subnet")
            when :vpc_id
              result.add_suggestion("Use ref(:vpc, :vpc_name, :id) to reference a VPC")
            when :security_group_ids
              result.add_suggestion("Use [ref(:security_group, :sg_name, :id)] for security groups")
            end
          end
        end

        result
      end
    end
  end
end
