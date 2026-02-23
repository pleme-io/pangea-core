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
    # Hash that transparently handles both string and symbol keys.
    # TerraformSynthesizer#synthesis returns symbol keys, but many tests
    # use string keys. This class makes both work seamlessly.
    class IndifferentHash < Hash
      def [](key)
        result = super(key.to_s)
        return result unless result.nil?

        key.respond_to?(:to_sym) ? super(key.to_sym) : nil
      end

      def dig(key, *rest)
        val = self[key]
        return val if rest.empty? || val.nil?

        val.respond_to?(:dig) ? val.dig(*rest) : nil
      end

      def has_key?(key)
        super(key.to_s) || (key.respond_to?(:to_sym) && super(key.to_sym))
      end
      alias_method :key?, :has_key?
      alias_method :include?, :has_key?

      def fetch(key, *args, &block)
        if has_key?(key)
          self[key]
        elsif args.any?
          args.first
        elsif block
          block.call(key)
        else
          raise KeyError, "key not found: #{key.inspect}"
        end
      end

      def self.deep_convert(obj)
        case obj
        when Hash
          result = IndifferentHash.new
          obj.each { |k, v| result[k.to_s] = deep_convert(v) }
          result
        when Array
          obj.map { |v| deep_convert(v) }
        else
          obj
        end
      end
    end
  end
end
