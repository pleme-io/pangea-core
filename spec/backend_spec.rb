# frozen_string_literal: true

require 'pangea/backend'

RSpec.describe Pangea::Backend do
  describe '.resolve' do
    it 'returns the explicit value when provided' do
      expect(described_class.resolve(explicit: 'magma')).to eq('magma')
      expect(described_class.resolve(explicit: 'tofu')).to eq('tofu')
    end

    it 'falls back to PANGEA_BACKEND env when no explicit flag' do
      ENV['PANGEA_BACKEND'] = 'magma'
      begin
        expect(described_class.resolve(explicit: nil)).to eq('magma')
      ensure
        ENV.delete('PANGEA_BACKEND')
      end
    end

    it 'falls back to pangea.yml backend: field' do
      expect(
        described_class.resolve(explicit: nil, yml_config: { 'backend' => 'magma' }),
      ).to eq('magma')
    end

    it 'defaults to tofu when nothing is set' do
      expect(described_class.resolve(explicit: nil)).to eq('tofu')
    end

    it 'rejects unknown backend names' do
      expect { described_class.resolve(explicit: 'opentofu') }
        .to raise_error(ArgumentError, /unknown backend/)
    end
  end

  describe 'BackendIncompatible' do
    it 'formats helpful error messages' do
      e = Pangea::Backend::BackendIncompatible.new(
        backend:      'tofu',
        feature:      'in-memory workspace chains',
        alternatives: ['magma'],
        hint:         'Switch to backend=magma.',
      )
      expect(e.message).to include('backend=tofu')
      expect(e.message).to include('in-memory workspace chains')
      expect(e.message).to include('Alternatives: backend=magma')
      expect(e.message).to include('Hint: Switch to backend=magma.')
    end
  end

  describe '.verify_compatible!' do
    it 'raises BackendIncompatible when in-memory is requested against tofu' do
      # We stub the capabilities probe to avoid needing tofu installed.
      allow(described_class).to receive(:capabilities).with('tofu').and_return(
        described_class::Capabilities.new(
          name:                          'tofu',
          version:                       '1.7.0',
          supported_protocols:           %w[tfplugin5 tfplugin6],
          input_formats:                 %w[hcl2 terraform-json],
          subcommands:                   %w[plan apply destroy],
          supports_in_memory_pipeline:   false,
          supports_workspace_chains:     false,
          raw:                           {},
        ),
      )
      expect {
        described_class.verify_compatible!('tofu', feature: :in_memory_pipeline)
      }.to raise_error(described_class::BackendIncompatible) do |e|
        expect(e.backend).to eq('tofu')
        expect(e.alternatives).to eq(['magma'])
      end
    end

    it 'accepts in-memory against magma' do
      allow(described_class).to receive(:capabilities).with('magma').and_return(
        described_class::Capabilities.new(
          name:                          'magma',
          version:                       '0.1.0',
          supported_protocols:           %w[tfplugin5 tfplugin6],
          input_formats:                 %w[pangea-ruby-inprocess terraform-json],
          subcommands:                   %w[plan apply destroy mcp flow],
          supports_in_memory_pipeline:   true,
          supports_workspace_chains:     true,
          raw:                           {},
        ),
      )
      expect {
        described_class.verify_compatible!('magma', feature: :in_memory_pipeline)
      }.not_to raise_error
    end
  end
end
