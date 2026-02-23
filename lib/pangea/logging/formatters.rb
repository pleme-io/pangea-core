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

require 'json'
require 'time'

module Pangea
  module Logging
    module Formatters
      LEVEL_ROLES = {
        debug: :debug,
        info: :info,
        warn: :warning,
        error: :error,
        fatal: :replace
      }.freeze

      EXCLUDED_CONTEXT_KEYS = %i[
        timestamp level message correlation_id pid thread_id ruby_version
      ].freeze

      def format_pretty(entry)
        timestamp = Time.parse(entry[:timestamp]).strftime('%Y-%m-%d %H:%M:%S.%L')
        level = entry[:level].ljust(5)
        level_role = LEVEL_ROLES[entry[:level].downcase.to_sym]

        context_str = build_context_string(entry)

        if defined?(Boreal) && level_role
          level = Boreal.paint(level, level_role)
        end

        "#{timestamp} [#{level}] #{entry[:message]}#{context_str}"
      end

      def format_json(entry)
        JSON.generate(entry)
      end

      def format_logfmt(entry)
        entry.map { |k, v|
          value = v.to_s.include?(' ') ? "\"#{v}\"" : v
          "#{k}=#{value}"
        }.join(' ')
      end

      def format_simple(entry)
        "#{entry[:level]} - #{entry[:message]}"
      end

      private

      def build_context_string(entry)
        context_items = entry.reject { |k, _| EXCLUDED_CONTEXT_KEYS.include?(k) }

        if context_items.any?
          " | " + context_items.map { |k, v| "#{k}=#{format_value(v)}" }.join(' ')
        else
          ""
        end
      end

      def format_value(value)
        case value
        when String
          value.include?(' ') ? "\"#{value}\"" : value
        when Hash
          "{#{value.size} items}"
        when Array
          "[#{value.size} items]"
        else
          value.to_s
        end
      end
    end
  end
end
