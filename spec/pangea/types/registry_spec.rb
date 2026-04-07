# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Pangea::Types::Registry do
  let(:registry) { described_class.instance }

  describe '#register' do
    it 'registers a type by name' do
      registry.register(:test_type, String)
      expect(registry[:test_type]).to be_a(Pangea::Types::Registry::TypeDefinition)
    end

    it 'accepts a block for constraints' do
      registry.register(:constrained_type, String) do
        format /\A[a-z]+\z/
        max_length 50
      end
      typedef = registry[:constrained_type]
      expect(typedef.constraints[:format]).to eq(/\A[a-z]+\z/)
      expect(typedef.constraints[:max_length]).to eq(50)
    end
  end

  describe '#[]' do
    it 'returns registered type' do
      registry.register(:lookup_test, Integer)
      expect(registry[:lookup_test].base_type).to eq(Integer)
    end

    it 'raises for unknown type' do
      expect { registry[:nonexistent_type_xyz] }.to raise_error(RuntimeError, /Unknown type/)
    end
  end
end

RSpec.describe Pangea::Types::Registry::TypeDefinition do
  let(:typedef) { described_class.new(:test, String) }

  describe '#format' do
    it 'sets format constraint' do
      typedef.format(/\A\d+\z/)
      expect(typedef.constraints[:format]).to eq(/\A\d+\z/)
    end
  end

  describe '#enum' do
    it 'sets enum constraint' do
      typedef.enum(%w[tcp udp])
      expect(typedef.constraints[:enum]).to eq(%w[tcp udp])
    end
  end

  describe '#range' do
    it 'sets range constraint' do
      typedef.range(1, 100)
      expect(typedef.constraints[:range]).to eq(1..100)
    end
  end

  describe '#max_length' do
    it 'sets max_length constraint' do
      typedef.max_length(255)
      expect(typedef.constraints[:max_length]).to eq(255)
    end
  end

  describe '#validation' do
    it 'adds validation block' do
      typedef.validation { |v| v.length > 0 }
      expect(typedef.validations.size).to eq(1)
    end

    it 'accumulates multiple validations' do
      typedef.validation { |v| v.length > 0 }
      typedef.validation { |v| v.length < 100 }
      expect(typedef.validations.size).to eq(2)
    end
  end

  describe 'attributes' do
    it 'exposes name' do
      expect(typedef.name).to eq(:test)
    end

    it 'exposes base_type' do
      expect(typedef.base_type).to eq(String)
    end
  end
end
