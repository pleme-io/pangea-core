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
  module Errors
    class PangeaError < StandardError
      attr_reader :context, :cause_chain, :timestamp

      def initialize(message, context: {}, cause: nil)
        super(message)
        @context = context
        @cause_chain = build_cause_chain(cause || self.cause)
        @timestamp = Time.now
      end

      def detailed_message
        lines = ["[#{@timestamp.iso8601}] #{self.class.name}: #{message}"]
        lines << "Context: #{format_context}" if @context.any?
        lines << "Cause chain:\n#{format_cause_chain}" if @cause_chain.any?
        lines.join("\n")
      end

      def to_h
        {
          error_type: self.class.name,
          message: message,
          context: @context,
          cause_chain: @cause_chain,
          timestamp: @timestamp.iso8601
        }
      end

      private

      def build_cause_chain(initial_cause)
        chain = []
        current = initial_cause
        depth = 0

        while current && depth < 10
          chain << {
            type: current.class.name,
            message: current.message,
            backtrace: current.backtrace&.first(3)
          }
          current = current.respond_to?(:cause) ? current.cause : nil
          depth += 1
        end

        chain
      end

      def format_context
        @context.map { |k, v| "  #{k}: #{v}" }.join("\n")
      end

      def format_cause_chain
        @cause_chain.map.with_index do |error, index|
          indent = "  " * (index + 1)
          "#{indent}→ #{error[:type]}: #{error[:message]}"
        end.join("\n")
      end
    end

    class ValidationError < PangeaError
      def self.invalid_attribute(resource, attribute, value, expected)
        new("#{resource}: Invalid #{attribute} '#{value}'. Expected: #{expected}",
            context: { resource: resource, attribute: attribute, value: value, expected: expected })
      end

      def self.missing_required(resource, attribute)
        new("#{resource}: Missing required attribute '#{attribute}'",
            context: { resource: resource, attribute: attribute })
      end

      def self.invalid_reference(source, target, reason)
        new("Invalid reference from #{source} to #{target}. Reason: #{reason}",
            context: { source: source, target: target, reason: reason })
      end

      def self.invalid_type(resource, attribute, expected_type, actual_type)
        new("#{resource}: Invalid type for '#{attribute}'. Expected: #{expected_type}, Got: #{actual_type}",
            context: { resource: resource, attribute: attribute, expected_type: expected_type, actual_type: actual_type })
      end

      def self.out_of_range(resource, attribute, value, range)
        new("#{resource}: Value '#{value}' for '#{attribute}' is out of range. Expected: #{range}",
            context: { resource: resource, attribute: attribute, value: value, range: range })
      end
    end

    class SynthesisError < PangeaError
      def self.invalid_template(template_name, reason)
        new("Failed to synthesize template '#{template_name}': #{reason}",
            context: { template_name: template_name, reason: reason })
      end

      def self.circular_dependency(resource1, resource2)
        new("Circular dependency detected between #{resource1} and #{resource2}",
            context: { resource1: resource1, resource2: resource2 })
      end
    end

    class ResourceNotFoundError < PangeaError
      def self.new(resource_type, resource_name)
        super("Resource not found: #{resource_type}.#{resource_name}",
              context: { resource_type: resource_type, resource_name: resource_name })
      end
    end
  end
end
