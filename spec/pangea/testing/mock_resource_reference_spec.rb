# frozen_string_literal: true

require 'spec_helper'
require 'pangea/testing'

RSpec.describe Pangea::Testing::MockResourceReference do
  let(:ref) { described_class.new('aws_vpc', 'main', { cidr_block: '10.0.0.0/16' }) }

  describe '#initialize' do
    it 'stores type, name, and attributes' do
      expect(ref.type).to eq('aws_vpc')
      expect(ref.name).to eq('main')
      expect(ref.attributes).to eq({ cidr_block: '10.0.0.0/16' })
    end

    it 'defaults attributes to empty hash' do
      r = described_class.new('aws_vpc', 'test')
      expect(r.attributes).to eq({})
    end
  end

  describe '#id' do
    it 'returns terraform id reference' do
      expect(ref.id).to eq('${aws_vpc.main.id}')
    end
  end

  describe '#arn' do
    it 'returns terraform arn reference' do
      expect(ref.arn).to eq('${aws_vpc.main.arn}')
    end
  end

  describe '#email' do
    it 'returns terraform email reference' do
      expect(ref.email).to eq('${aws_vpc.main.email}')
    end
  end

  describe '#endpoint' do
    it 'returns terraform endpoint reference' do
      expect(ref.endpoint).to eq('${aws_vpc.main.endpoint}')
    end
  end

  describe '#ipv4_address' do
    it 'returns terraform ipv4_address reference' do
      expect(ref.ipv4_address).to eq('${aws_vpc.main.ipv4_address}')
    end
  end

  describe '#to_h' do
    it 'returns hash with type, name, and attributes' do
      expect(ref.to_h).to eq({
        type: 'aws_vpc',
        name: 'main',
        attributes: { cidr_block: '10.0.0.0/16' }
      })
    end
  end

  describe '#method_missing' do
    it 'returns attribute value when symbol key exists' do
      expect(ref.cidr_block).to eq('10.0.0.0/16')
    end

    it 'returns attribute value when string key exists' do
      r = described_class.new('aws_vpc', 'main', { 'label' => 'test-vpc' })
      expect(r.label).to eq('test-vpc')
    end

    it 'returns terraform reference for unknown attributes' do
      expect(ref.some_unknown_attr).to eq('${aws_vpc.main.some_unknown_attr}')
    end
  end

  describe '#respond_to_missing?' do
    it 'returns true for all methods' do
      expect(ref.respond_to?(:anything)).to be true
      expect(ref.respond_to?(:completely_random)).to be true
    end
  end
end
