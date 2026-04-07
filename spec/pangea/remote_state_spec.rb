# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Pangea::RemoteState do
  before { described_class.reset! }

  describe '.configure' do
    it 'sets root bucket and region' do
      described_class.configure(bucket: 'my-bucket', region: 'eu-west-1')
      expect(described_class.instance_variable_get(:@root_bucket)).to eq('my-bucket')
      expect(described_class.instance_variable_get(:@root_region)).to eq('eu-west-1')
    end

    it 'defaults region to us-east-1' do
      described_class.configure(bucket: 'my-bucket')
      expect(described_class.instance_variable_get(:@root_region)).to eq('us-east-1')
    end
  end

  describe '.output' do
    it 'raises ArgumentError when no bucket configured' do
      expect {
        described_class.output(template: 'test', output: :vpc_id)
      }.to raise_error(ArgumentError, /No bucket configured/)
    end

    it 'returns nil when state file does not exist' do
      allow(described_class).to receive(:fetch_state).and_return(nil)
      result = described_class.output(
        template: 'nonexistent-template',
        output: :vpc_id,
        bucket: 'fake-bucket',
        region: 'us-east-1',
      )
      expect(result).to be_nil
    end

    it 'extracts output value from fetched state' do
      state = {
        'outputs' => {
          'vpc_id' => { 'value' => 'vpc-abc123' }
        }
      }
      allow(described_class).to receive(:fetch_state).and_return(state)
      result = described_class.output(
        template: 'my-template',
        output: :vpc_id,
        bucket: 'my-bucket'
      )
      expect(result).to eq('vpc-abc123')
    end

    it 'tracks dependency when fetching state' do
      state = { 'outputs' => { 'id' => { 'value' => '123' } } }
      allow(described_class).to receive(:fetch_state).and_return(state)
      described_class.output(template: 'dep-template', output: :id, bucket: 'b')
      expect(described_class.dependency_graph).to have_key('dep-template')
    end

    it 'uses configured root bucket when no bucket passed' do
      described_class.configure(bucket: 'root-bucket')
      allow(described_class).to receive(:fetch_state).and_return(nil)
      described_class.output(template: 'test', output: :id)
      expect(described_class).to have_received(:fetch_state).with(
        hash_including(bucket: 'root-bucket')
      )
    end

    it 'uses custom state_key when provided' do
      allow(described_class).to receive(:fetch_state).and_return(nil)
      described_class.output(
        template: 'test',
        output: :id,
        bucket: 'b',
        state_key: 'custom/path/state.tfstate'
      )
      expect(described_class).to have_received(:fetch_state).with(
        hash_including(key: 'custom/path/state.tfstate')
      )
    end
  end

  describe '.from' do
    it 'delegates to .output' do
      described_class.configure(bucket: 'b')
      allow(described_class).to receive(:fetch_state).and_return(nil)
      described_class.from('template-name', :vpc_id)
      expect(described_class).to have_received(:fetch_state)
    end
  end

  describe '.from_template' do
    it 'extracts bucket from workspace config with state_config' do
      ws = double('ws')
      allow(ws).to receive(:respond_to?).with(:state_config).and_return(true)
      allow(ws).to receive(:respond_to?).with(:raw_config).and_return(false)
      allow(ws).to receive(:state_config).and_return({ 'bucket' => 'ws-bucket', 'region' => 'eu-west-1' })
      allow(described_class).to receive(:fetch_state).and_return(nil)

      described_class.from_template(ws, template: 'tpl', output: :id)
      expect(described_class).to have_received(:fetch_state).with(
        hash_including(bucket: 'ws-bucket', region: 'eu-west-1')
      )
    end

    it 'extracts bucket from workspace config with raw_config' do
      ws = double('ws')
      allow(ws).to receive(:respond_to?).with(:state_config).and_return(false)
      allow(ws).to receive(:respond_to?).with(:raw_config).and_return(true)
      allow(ws).to receive(:raw_config).and_return({
        'state' => { 's3' => { 'bucket' => 'raw-bucket', 'region' => 'ap-southeast-1' } }
      })
      allow(described_class).to receive(:fetch_state).and_return(nil)

      described_class.from_template(ws, template: 'tpl', output: :id)
      expect(described_class).to have_received(:fetch_state).with(
        hash_including(bucket: 'raw-bucket', region: 'ap-southeast-1')
      )
    end

    it 'raises when bucket cannot be determined' do
      ws = double('ws')
      allow(ws).to receive(:respond_to?).and_return(false)

      expect {
        described_class.from_template(ws, template: 'tpl', output: :id)
      }.to raise_error(ArgumentError, /Cannot determine state bucket/)
    end

    it 'uses root_bucket when configured' do
      described_class.configure(bucket: 'root-b', region: 'us-west-2')
      ws = double('ws')
      allow(ws).to receive(:respond_to?).and_return(false)
      allow(described_class).to receive(:fetch_state).and_return(nil)

      described_class.from_template(ws, template: 'tpl', output: :id)
      expect(described_class).to have_received(:fetch_state).with(
        hash_including(bucket: 'root-b', region: 'us-west-2')
      )
    end
  end

  describe '.extract_output' do
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
  end

  describe '.dependency_graph' do
    it 'starts empty' do
      expect(described_class.dependency_graph).to eq({})
    end

    it 'returns a copy, not the internal hash' do
      graph = described_class.dependency_graph
      graph['test'] = []
      expect(described_class.dependency_graph).not_to have_key('test')
    end
  end

  describe '.reset!' do
    it 'clears all tracked dependencies and config' do
      described_class.configure(bucket: 'b', region: 'r')
      described_class.instance_variable_get(:@dependencies)['test'] = ['dep']
      described_class.reset!
      expect(described_class.dependency_graph).to eq({})
      expect(described_class.instance_variable_get(:@root_bucket)).to be_nil
      expect(described_class.instance_variable_get(:@root_region)).to be_nil
    end
  end
end
