# frozen_string_literal: true

require 'pangea/magma'
require 'pangea/magma/matchers'

RSpec.describe Pangea::Magma do
  describe '.installed?' do
    it 'returns a boolean' do
      expect([true, false]).to include(described_class.installed?)
    end
  end

  describe '.binary' do
    after { described_class.reset! }

    it 'defaults to magma' do
      described_class.reset!
      ENV.delete('MAGMA_BINARY')
      expect(described_class.binary).to eq('magma')
    end

    it 'honors MAGMA_BINARY env override' do
      described_class.reset!
      ENV['MAGMA_BINARY'] = '/custom/path/magma'
      begin
        expect(described_class.binary).to eq('/custom/path/magma')
      ensure
        ENV.delete('MAGMA_BINARY')
      end
    end
  end

  describe 'when magma binary is reachable' do
    before do
      skip 'magma not installed' unless described_class.installed?
    end

    it 'reports capabilities with the expected schema' do
      caps = described_class.capabilities
      expect(caps['tool']).to eq('magma')
      expect(caps['schema_version']).to eq(1)
      expect(caps['workspace_chain_supported']).to be(true)
      expect(caps['in_memory_pipeline_supported']).to be(true)
    end
  end
end

RSpec.describe Pangea::Magma::Matchers do
  include described_class

  describe 'plan_cleanly_under_magma matcher' do
    it 'has the right description' do
      matcher = plan_cleanly_under_magma
        .with_provider('hashicorp/aws')
        .with_at_least(3).resource_changes
        .with_resource_type('aws_vpc')
      expect(matcher.description).to include('plan cleanly under magma')
      expect(matcher.description).to include('hashicorp/aws')
      expect(matcher.description).to include('≥3 resource_changes')
      expect(matcher.description).to include('aws_vpc')
    end

    context 'when magma is not installed' do
      before do
        allow(Pangea::Magma).to receive(:installed?).and_return(false)
      end

      it 'reports a skip-style failure message rather than crashing' do
        matcher = plan_cleanly_under_magma
        expect(matcher.matches?('/nonexistent')).to be(false)
        expect(matcher.failure_message).to include('magma binary not installed')
      end
    end
  end

  describe 'be_compatible_with_backend matcher' do
    it 'passes for the default tofu backend with no requires' do
      allow(Pangea::Backend).to receive(:capabilities).with('tofu').and_return(
        Pangea::Backend::Capabilities.new(
          name: 'tofu', version: '1.7', supported_protocols: ['tfplugin5','tfplugin6'],
          input_formats: ['hcl2','terraform-json'], subcommands: ['plan'],
          supports_in_memory_pipeline: false, supports_workspace_chains: false, raw: {},
        ),
      )
      expect(be_compatible_with_backend('tofu').matches?).to be(true)
    end

    it 'fails for tofu when in_memory_pipeline is required' do
      allow(Pangea::Backend).to receive(:capabilities).with('tofu').and_return(
        Pangea::Backend::Capabilities.new(
          name: 'tofu', version: '1.7', supported_protocols: ['tfplugin5','tfplugin6'],
          input_formats: ['hcl2','terraform-json'], subcommands: ['plan'],
          supports_in_memory_pipeline: false, supports_workspace_chains: false, raw: {},
        ),
      )
      matcher = be_compatible_with_backend('tofu').requiring_feature(:in_memory_pipeline)
      expect(matcher.matches?).to be(false)
      expect(matcher.failure_message).to include('in-memory workspace chains')
    end
  end
end
