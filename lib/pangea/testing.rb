# frozen_string_literal: true

# Entry point for Pangea shared testing infrastructure.
# Require this file in your spec_helper.rb to get access to:
#
#   Pangea::Testing::SynthesisTestHelpers  — synthesis validation helpers
#   Pangea::Testing::MockTerraformSynthesizer — mock synthesizer
#   Pangea::Testing::MockResourceReference — mock resource ref
#   Pangea::Testing::IndifferentHash — string/symbol-agnostic hash
#   Pangea::Testing::SpecSetup.configure! — shared RSpec configuration
#
# Usage in spec_helper.rb:
#
#   require 'pangea/testing'
#   Pangea::Testing::SpecSetup.configure!(indifferent: true)
#
require_relative 'testing/indifferent_hash'
require_relative 'testing/mock_resource_reference'
require_relative 'testing/mock_terraform_synthesizer'
require_relative 'testing/synthesis_test_helpers'
require_relative 'testing/resource_examples'
require_relative 'testing/spec_setup'
