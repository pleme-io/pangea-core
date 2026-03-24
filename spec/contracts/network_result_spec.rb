# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Pangea::Contracts::NetworkResult do
  let(:result) { described_class.new }

  # Stub resource reference with an id method
  let(:vpc_ref) { double('vpc_ref', id: 'vpc-123') }
  let(:sg_ref) { double('sg_ref', id: 'sg-456') }
  let(:subnet_a_ref) { double('subnet_a_ref', id: 'subnet-a') }
  let(:subnet_b_ref) { double('subnet_b_ref', id: 'subnet-b') }

  describe '#vpc and #sg' do
    it 'starts as nil' do
      expect(result.vpc).to be_nil
      expect(result.sg).to be_nil
    end

    it 'can be set via accessor' do
      result.vpc = vpc_ref
      result.sg = sg_ref
      expect(result.vpc).to eq(vpc_ref)
      expect(result.sg).to eq(sg_ref)
    end
  end

  describe '#add_subnet and #subnets' do
    it 'starts with empty subnets' do
      expect(result.subnets).to eq([])
    end

    it 'accumulates subnets in order' do
      result.add_subnet(:subnet_a, subnet_a_ref)
      result.add_subnet(:subnet_b, subnet_b_ref)
      expect(result.subnets).to eq([subnet_a_ref, subnet_b_ref])
    end
  end

  describe '#subnet_ids' do
    it 'returns ids from subnet references' do
      result.add_subnet(:subnet_a, subnet_a_ref)
      result.add_subnet(:subnet_b, subnet_b_ref)
      expect(result.subnet_ids).to eq(%w[subnet-a subnet-b])
    end
  end

  describe '#public_subnets' do
    it 'is an alias for subnets' do
      result.add_subnet(:subnet_a, subnet_a_ref)
      expect(result.public_subnets).to eq(result.subnets)
    end
  end

  describe '#[]' do
    before do
      result.vpc = vpc_ref
      result.sg = sg_ref
      result.add_subnet(:subnet_a, subnet_a_ref)
    end

    it 'accesses vpc by key' do
      expect(result[:vpc]).to eq(vpc_ref)
    end

    it 'accesses sg by key' do
      expect(result[:sg]).to eq(sg_ref)
    end

    it 'accesses public_subnets by key' do
      expect(result[:public_subnets]).to eq([subnet_a_ref])
    end

    it 'accesses subnet_ids by key' do
      expect(result[:subnet_ids]).to eq(['subnet-a'])
    end

    it 'accesses individual subnets by name' do
      expect(result[:subnet_a]).to eq(subnet_a_ref)
    end

    it 'returns nil for unknown keys' do
      expect(result[:unknown]).to be_nil
    end

    it 'works with string keys' do
      expect(result['vpc']).to eq(vpc_ref)
    end
  end

  describe '#to_h' do
    it 'includes only non-nil values' do
      result.vpc = vpc_ref
      result.add_subnet(:subnet_a, subnet_a_ref)

      hash = result.to_h
      expect(hash).to have_key(:vpc)
      expect(hash).to have_key(:subnet_a)
      expect(hash).not_to have_key(:sg)
    end
  end

  describe '#key? / #has_key? / #include?' do
    before { result.vpc = vpc_ref }

    it 'returns true for present keys' do
      expect(result.key?(:vpc)).to be true
      expect(result.has_key?(:vpc)).to be true
      expect(result.include?(:vpc)).to be true
    end

    it 'returns false for missing keys' do
      expect(result.key?(:sg)).to be false
    end
  end

  describe '#dig' do
    it 'delegates to to_h.dig' do
      result.vpc = vpc_ref
      expect(result.dig(:vpc)).to eq(vpc_ref)
    end
  end

  describe '#select' do
    it 'delegates to to_h.select' do
      result.vpc = vpc_ref
      result.add_subnet(:subnet_a, subnet_a_ref)
      result.add_subnet(:subnet_b, subnet_b_ref)

      subnet_entries = result.select { |k, _| k.to_s.start_with?('subnet_') }
      expect(subnet_entries.size).to eq(2)
    end
  end

  describe '#validate!' do
    it 'raises ContractError when vpc is nil' do
      expect { result.validate! }.to raise_error(
        Pangea::Contracts::ContractError, /vpc/
      )
    end

    it 'succeeds when vpc is set' do
      result.vpc = vpc_ref
      expect { result.validate! }.not_to raise_error
    end
  end
end
