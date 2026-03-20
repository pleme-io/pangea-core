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
      def initialize
        @errors = []
        @warnings = []
        @suggestions = []
        @finalized = false
      end

      # Return frozen copies so callers cannot mutate internal state
      def errors
        @errors.frozen? ? @errors : @errors.dup.freeze
      end

      def warnings
        @warnings.frozen? ? @warnings : @warnings.dup.freeze
      end

      def suggestions
        @suggestions.frozen? ? @suggestions : @suggestions.dup.freeze
      end

      def valid?
        @errors.empty?
      end

      def add_error(message)
        raise FrozenError, "cannot modify finalized ValidationResult" if @finalized

        @errors << message
      end

      def add_warning(message)
        raise FrozenError, "cannot modify finalized ValidationResult" if @finalized

        @warnings << message
      end

      def add_suggestion(message)
        raise FrozenError, "cannot modify finalized ValidationResult" if @finalized

        @suggestions << message
      end

      # Freeze the result, preventing further mutation.
      # After finalize!, add_error/add_warning/add_suggestion will raise FrozenError.
      def finalize!
        @errors.freeze
        @warnings.freeze
        @suggestions.freeze
        @finalized = true
        self
      end

      def finalized?
        @finalized
      end

      def to_s
        output = []

        errs = @errors
        warns = @warnings
        suggs = @suggestions

        if errs.any?
          output << "Errors:"
          errs.each { |e| output << "  - #{e}" }
        end

        if warns.any?
          output << "\nWarnings:"
          warns.each { |w| output << "  - #{w}" }
        end

        if suggs.any?
          output << "\nSuggestions:"
          suggs.each { |s| output << "  - #{s}" }
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
