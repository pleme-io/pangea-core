# frozen_string_literal: true

require 'spec_helper'
require 'pangea/testing/architecture_spec_generator'

RSpec.describe Pangea::Testing::ArchitectureSpecGenerator do
  let(:basic_generator) do
    described_class.new(
      module_name: 'Pangea::Architectures::TestArch',
      required_config: { name: 'test', region: 'us-east-1' },
      expected_resources: {
        'aws_vpc' => ['test-vpc'],
        'aws_subnet' => ['test-public', 'test-private'],
      },
      expected_refs: [:vpc, :subnet],
      required_tags: %w[ManagedBy Purpose],
    )
  end

  let(:security_generator) do
    described_class.new(
      module_name: 'Pangea::Architectures::SecureArch',
      required_config: { name: 'secure' },
      security_invariants: [
        { type: :no_wildcard_actions },
        { type: :no_public_ssh },
        { type: :encrypted_volumes },
      ],
    )
  end

  let(:minimal_generator) do
    described_class.new(module_name: 'Pangea::Architectures::Minimal')
  end

  describe '#generate' do
    it 'produces valid Ruby spec code' do
      output = basic_generator.generate
      expect(output).to include('RSpec.describe Pangea::Architectures::TestArch')
      expect(output).to include('include Pangea::Testing::SynthesisTestHelpers')
    end

    it 'includes resource existence tests' do
      output = basic_generator.generate
      expect(output).to include("creates aws_vpc test-vpc")
      expect(output).to include("creates aws_subnet test-public")
      expect(output).to include("creates aws_subnet test-private")
    end

    it 'includes determinism test' do
      output = basic_generator.generate
      expect(output).to include('produces deterministic output')
    end

    it 'includes tag test' do
      output = basic_generator.generate
      expect(output).to include('applies required tags')
      expect(output).to include('ManagedBy')
      expect(output).to include('Purpose')
    end

    it 'includes ref assertions' do
      output = basic_generator.generate
      expect(output).to include('returns all expected resource references')
      expect(output).to include('have_key(:vpc)')
      expect(output).to include('have_key(:subnet)')
    end

    it 'includes validation tests' do
      output = basic_generator.generate
      expect(output).to include('raises on empty config')
    end
  end

  describe '#generate_synthesis' do
    it 'generates only synthesis spec' do
      output = basic_generator.generate_synthesis
      expect(output).to include('RSpec.describe')
      expect(output).not_to include('security invariants')
    end
  end

  describe '#generate_security' do
    it 'generates security spec with invariants' do
      output = security_generator.generate_security
      expect(output).to include('security invariants')
    end

    it 'generates no_wildcard_actions test' do
      output = security_generator.generate_security
      expect(output).to include('never uses wildcard actions')
    end

    it 'generates no_public_ssh test' do
      output = security_generator.generate_security
      expect(output).to include('does not allow SSH from 0.0.0.0/0')
    end

    it 'generates encrypted_volumes test' do
      output = security_generator.generate_security
      expect(output).to include('uses encrypted volumes')
    end

    it 'returns nil when no security invariants' do
      output = minimal_generator.send(:security_spec)
      expect(output).to be_nil
    end
  end

  describe 'unknown security invariant type' do
    it 'generates a comment for unknown types' do
      gen = described_class.new(
        module_name: 'Test',
        security_invariants: [{ type: :unknown_check }]
      )
      output = gen.generate_security
      expect(output).to include('Unknown invariant')
    end
  end

  describe 'format_hash' do
    it 'formats nested hashes' do
      gen = described_class.new(module_name: 'Test')
      result = gen.send(:format_hash, { a: { b: 'c' } })
      expect(result).to include('a:')
      expect(result).to include("b: 'c'")
    end

    it 'handles empty hashes' do
      gen = described_class.new(module_name: 'Test')
      expect(gen.send(:format_hash, {})).to eq('{}')
    end

    it 'formats symbols correctly' do
      gen = described_class.new(module_name: 'Test')
      result = gen.send(:format_hash, { type: :resource })
      expect(result).to include('type: :resource')
    end

    it 'formats arrays with inspect' do
      gen = described_class.new(module_name: 'Test')
      result = gen.send(:format_hash, { items: [1, 2, 3] })
      expect(result).to include('[1, 2, 3]')
    end
  end
end
