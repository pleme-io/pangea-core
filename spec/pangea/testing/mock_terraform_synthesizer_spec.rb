# frozen_string_literal: true

require 'spec_helper'
require 'pangea/testing'

RSpec.describe Pangea::Testing::MockTerraformSynthesizer do
  let(:synthesizer) { described_class.new }

  describe '#initialize' do
    it 'starts with empty resources' do
      expect(synthesizer.resources).to eq({})
    end

    it 'starts with empty data_sources' do
      expect(synthesizer.data_sources).to eq({})
    end

    it 'starts with empty outputs' do
      expect(synthesizer.outputs).to eq({})
    end
  end

  describe '#method_missing' do
    it 'records resource calls and returns MockResourceReference' do
      result = synthesizer.aws_vpc(:main, { cidr_block: '10.0.0.0/16' })
      expect(result).to be_a(Pangea::Testing::MockResourceReference)
      expect(result.type).to eq('aws_vpc')
      expect(result.name).to eq('main')
    end

    it 'records resource in resources hash' do
      synthesizer.aws_vpc(:main, { cidr_block: '10.0.0.0/16' })
      expect(synthesizer.resources).to have_key('aws_vpc')
      expect(synthesizer.resources['aws_vpc']).to have_key('main')
      expect(synthesizer.resources['aws_vpc']['main']).to eq({ cidr_block: '10.0.0.0/16' })
    end

    it 'handles multiple resources of same type' do
      synthesizer.aws_subnet(:public, { cidr: '10.0.1.0/24' })
      synthesizer.aws_subnet(:private, { cidr: '10.0.2.0/24' })
      expect(synthesizer.resources['aws_subnet'].keys).to contain_exactly('public', 'private')
    end

    it 'handles calls without config hash' do
      result = synthesizer.hcloud_server(:web)
      expect(result).to be_a(Pangea::Testing::MockResourceReference)
      expect(synthesizer.resources['hcloud_server']['web']).to eq({})
    end
  end

  describe '#synthesis' do
    it 'returns hash with resource key when resources exist' do
      synthesizer.aws_vpc(:main, { cidr: '10.0.0.0/16' })
      result = synthesizer.synthesis
      expect(result).to have_key('resource')
      expect(result['resource']).to have_key('aws_vpc')
    end

    it 'returns empty hash when nothing is defined' do
      expect(synthesizer.synthesis).to eq({})
    end

    it 'does not include resource key when empty' do
      expect(synthesizer.synthesis).not_to have_key('resource')
    end
  end

  describe '#respond_to_missing?' do
    it 'returns true for all methods' do
      expect(synthesizer.respond_to?(:any_method)).to be true
    end
  end
end
