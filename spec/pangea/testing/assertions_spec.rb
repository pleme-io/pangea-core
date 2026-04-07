# frozen_string_literal: true

require 'spec_helper'
require 'pangea/testing/assertions'

RSpec.describe Pangea::Testing::Assertions do
  include described_class

  describe '#assert_terraform_structure' do
    let(:valid_result) do
      {
        'resource' => {
          'aws_vpc' => {
            'main' => { 'cidr_block' => '10.0.0.0/16' }
          }
        }
      }
    end

    it 'returns resource config for valid structure' do
      config = assert_terraform_structure(valid_result, 'aws_vpc', 'main')
      expect(config['cidr_block']).to eq('10.0.0.0/16')
    end

    it 'works with symbol keys' do
      sym_result = {
        resource: {
          aws_vpc: {
            main: { cidr_block: '10.0.0.0/16' }
          }
        }
      }
      config = assert_terraform_structure(sym_result, :aws_vpc, :main)
      expect(config[:cidr_block]).to eq('10.0.0.0/16')
    end

    it 'fails for missing resource type' do
      expect {
        assert_terraform_structure(valid_result, 'aws_subnet', 'main')
      }.to raise_error(RSpec::Expectations::ExpectationNotMetError)
    end
  end

  describe '#assert_resource_reference' do
    let(:ref) do
      Pangea::Resources::ResourceReference.new(
        type: 'aws_vpc',
        name: :main,
        resource_attributes: {},
        outputs: { id: '${aws_vpc.main.id}' }
      )
    end

    it 'validates type and name' do
      result = assert_resource_reference(ref, 'aws_vpc', :main)
      expect(result).to eq(ref)
    end

    it 'validates expected outputs' do
      result = assert_resource_reference(ref, 'aws_vpc', :main, { id: '${aws_vpc.main.id}' })
      expect(result).to eq(ref)
    end

    it 'fails for wrong type' do
      expect {
        assert_resource_reference(ref, 'aws_subnet', :main)
      }.to raise_error(RSpec::Expectations::ExpectationNotMetError)
    end
  end

  describe '#assert_tags_present' do
    it 'validates tags with string keys' do
      config = { 'tags' => { 'Name' => 'test', 'Env' => 'dev' } }
      expect { assert_tags_present(config, { Name: 'test' }) }.not_to raise_error
    end

    it 'validates tags with symbol keys' do
      config = { tags: { Name: 'test' } }
      expect { assert_tags_present(config, { Name: 'test' }) }.not_to raise_error
    end

    it 'fails when tags are missing' do
      config = { 'tags' => nil }
      expect {
        assert_tags_present(config, { Name: 'test' })
      }.to raise_error(RSpec::Expectations::ExpectationNotMetError)
    end
  end
end
