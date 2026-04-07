# frozen_string_literal: true

require 'spec_helper'
require 'pangea/testing/resource_examples'

RSpec.describe Pangea::Testing::ResourceExamples do
  it 'defines the shared example group' do
    groups = RSpec.world.shared_example_group_registry.send(:shared_example_groups)
    # The shared example 'a pangea resource' should be registered
    has_shared_example = groups.values.any? { |g| g.key?('a pangea resource') }
    expect(has_shared_example).to be true
  end
end
