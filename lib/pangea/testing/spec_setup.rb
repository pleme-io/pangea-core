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

require_relative 'synthesis_test_helpers'
require_relative 'indifferent_hash'

module Pangea
  module Testing
    # Shared RSpec configuration for all Pangea gems.
    # Call Pangea::Testing::SpecSetup.configure! in your spec_helper.rb
    # to get consistent test infrastructure across all provider gems.
    module SpecSetup
      def self.configure!(indifferent: false)
        # Patch TerraformSynthesizer for indifferent key access if requested
        if indifferent && defined?(TerraformSynthesizer)
          TerraformSynthesizer.class_eval do
            alias_method :_original_synthesis, :synthesis unless method_defined?(:_original_synthesis)

            define_method(:synthesis) do
              Pangea::Testing::IndifferentHash.deep_convert(_original_synthesis)
            end
          end
        end

        RSpec.configure do |config|
          config.example_status_persistence_file_path = '.rspec_status'
          config.disable_monkey_patching!
          config.expect_with :rspec do |c|
            c.syntax = :expect
          end
          config.include Pangea::Testing::SynthesisTestHelpers
          config.before(:suite) { ENV['PANGEA_ENV'] = 'test' }
          config.formatter = :progress
          config.color = true
          config.filter_run_when_matching :focus
          config.run_all_when_everything_filtered = true
          config.order = :random
          Kernel.srand config.seed
          config.warnings = false
        end
      end
    end
  end
end
