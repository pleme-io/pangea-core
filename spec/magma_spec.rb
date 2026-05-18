# frozen_string_literal: true

require 'pangea/magma'
require 'pangea/magma/matchers'
require 'pangea/magma/test_support'

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
    before(:all) do
      Pangea::Magma::TestSupport.skip_unless_installed!(self.class)
    end

    it 'reports capabilities with the expected schema' do
      caps = described_class.capabilities
      expect(caps['tool']).to eq('magma')
      expect(caps['schema_version']).to eq(1)
      expect(caps['workspace_chain_supported']).to be(true)
      expect(caps['in_memory_pipeline_supported']).to be(true)
    end
  end

  describe 'error hierarchy' do
    it 'has Pangea::Magma::Error as the umbrella for every typed failure' do
      expect(Pangea::Magma::VerificationFailed.new).to be_a(Pangea::Magma::Error)
      expect(Pangea::Magma::Migration::InvariantViolation.new).to be_a(Pangea::Magma::Error)
      sub_err = Pangea::Magma::Runner::SubprocessError.new(
        command: %w[magma x], exit_code: 99, stdout: 'out', stderr: 'err',
      )
      expect(sub_err).to be_a(Pangea::Magma::Error)
    end

    it 'lets callers rescue every typed failure via Pangea::Magma::Error' do
      [
        Pangea::Magma::VerificationFailed.new('v'),
        Pangea::Magma::Migration::InvariantViolation.new('m'),
        Pangea::Magma::Runner::SubprocessError.new(
          command: %w[magma x], exit_code: 1, stdout: '', stderr: '',
        ),
      ].each do |err|
        rescued = begin
                    raise err
                  rescue Pangea::Magma::Error => e
                    e.class
                  end
        expect(rescued).to eq(err.class)
      end
    end
  end

  describe 'with a mocked binary (no real magma needed)' do
    it 'parses JSON stdout from a stubbed binary' do
      Pangea::Magma::TestSupport.mock_magma_binary(
        script_stdout: '{"hello":"mocked"}',
      ) do
        out = Pangea::Magma::Runner.invoke('capabilities')
        expect(out).to eq('hello' => 'mocked')
      end
    end

    it 'raises Pangea::Magma::Error when the stubbed binary fails' do
      expect {
        Pangea::Magma::TestSupport.mock_magma_binary(
          script_stdout: 'boom', script_exit_code: 2,
        ) do
          Pangea::Magma::Runner.invoke('flow')
        end
      }.to raise_error(Pangea::Magma::Error, /exit 2/)
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
