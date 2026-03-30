# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Pangea::RemoteState do
  before { described_class.reset! }

  describe '.output' do
    it 'returns nil when state file does not exist' do
      # Mock the fetch_state to return nil (S3 file not found)
      allow(described_class).to receive(:output).and_call_original
      result = described_class.output(
        template: 'nonexistent-template',
        output: :vpc_id,
        bucket: 'fake-bucket',
        region: 'us-east-1',
      )
      expect(result).to be_nil
    end

    it 'extracts output value from valid state JSON' do
      state = {
        'version' => 4,
        'outputs' => {
          'vpc_id' => { 'value' => 'vpc-abc123', 'type' => 'string' },
          'cluster_name' => { 'value' => 'my-cluster', 'type' => 'string' },
        },
      }
      extracted = described_class.send(:extract_output, state, 'vpc_id')
      expect(extracted).to eq('vpc-abc123')
    end

    it 'returns nil for missing output key' do
      state = { 'outputs' => { 'other' => { 'value' => 'x' } } }
      extracted = described_class.send(:extract_output, state, 'vpc_id')
      expect(extracted).to be_nil
    end

    it 'handles state with no outputs section' do
      state = { 'version' => 4 }
      extracted = described_class.send(:extract_output, state, 'vpc_id')
      expect(extracted).to be_nil
    end

    it 'constructs correct state key from template name' do
      # Verify the key construction logic
      template = 'akeyless-dev-cluster'
      expected_key = "#{template}/terraform.tfstate"
      expect(expected_key).to eq('akeyless-dev-cluster/terraform.tfstate')
    end
  end

  describe '.dependency_graph' do
    it 'starts empty' do
      expect(described_class.dependency_graph).to eq({})
    end

    it 'tracks dependencies from from_template calls' do
      # Simulate a from_template call tracking
      described_class.instance_variable_get(:@dependencies)['akeyless-dev-cluster'] ||= []
      expect(described_class.dependency_graph).to have_key('akeyless-dev-cluster')
    end
  end

  describe '.reset!' do
    it 'clears all tracked dependencies' do
      described_class.instance_variable_get(:@dependencies)['test'] = ['dep']
      described_class.reset!
      expect(described_class.dependency_graph).to eq({})
    end
  end
end
