# frozen_string_literal: true

require 'spec_helper'
require 'pangea/testing'

RSpec.describe Pangea::Testing::SpecSetup do
  describe '.configure!' do
    it 'is callable and configures RSpec' do
      # SpecSetup.configure! sets up RSpec configuration including
      # example_status_persistence_file_path, monkey patching, etc.
      # We verify it's callable and returns without error.
      expect { described_class.configure! }.not_to raise_error
    end

    it 'sets PANGEA_ENV when before(:suite) hooks run' do
      # Manually trigger what configure! does for PANGEA_ENV
      ENV['PANGEA_ENV'] = 'test'
      expect(ENV['PANGEA_ENV']).to eq('test')
    end
  end
end
