# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Pangea::Resources::BaseComputedAttributes do
  let(:resource_ref) do
    Pangea::Resources::ResourceReference.new(
      type: 'aws_vpc',
      name: :main,
      resource_attributes: { tags: { Name: 'test-vpc' } }
    )
  end

  let(:computed) { described_class.new(resource_ref) }

  describe '#id' do
    it 'returns terraform id reference via resource_ref' do
      expect(computed.id).to eq('${aws_vpc.main.id}')
    end
  end

  describe '#terraform_resource_name' do
    it 'returns type.name format' do
      expect(computed.terraform_resource_name).to eq('aws_vpc.main')
    end
  end

  describe '#tags' do
    it 'returns tags from resource attributes' do
      expect(computed.tags).to eq({ Name: 'test-vpc' })
    end

    it 'returns empty hash when no tags in attributes' do
      ref = Pangea::Resources::ResourceReference.new(
        type: 'aws_vpc',
        name: :main,
        resource_attributes: {}
      )
      c = described_class.new(ref)
      expect(c.tags).to eq({})
    end
  end

  describe '#resource_ref' do
    it 'exposes the resource reference' do
      expect(computed.resource_ref).to eq(resource_ref)
    end
  end
end
