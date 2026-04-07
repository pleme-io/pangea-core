# frozen_string_literal: true

require 'spec_helper'
require 'pangea/testing/spec_generator'

RSpec.describe Pangea::Testing::SpecGenerator do
  let(:basic_generator) do
    described_class.new(
      provider_module: 'Pangea::Resources::AWS',
      resource_type: 'aws_vpc',
      required_attributes: { name: 'test-vpc', cidr_block: '10.0.0.0/16' },
      expected_outputs: [:id, :arn, :cidr_block],
    )
  end

  let(:full_generator) do
    described_class.new(
      provider_module: 'Pangea::Resources::AWS',
      resource_type: 'aws_iam_instance_profile',
      required_attributes: { name: 'test-profile', role: 'test-role' },
      optional_attributes: { path: '/custom/' },
      expected_outputs: [:id, :arn, :name],
      mutually_exclusive: [[:name, :name_prefix]],
      terraform_ref_fields: [:role],
      supports_tags: true,
    )
  end

  describe 'initialization' do
    it 'creates with required config' do
      expect(basic_generator.config[:resource_type]).to eq('aws_vpc')
    end

    it 'raises without provider_module' do
      expect {
        described_class.new(resource_type: 'test', required_attributes: {})
      }.to raise_error(ArgumentError, /provider_module/)
    end

    it 'raises without resource_type' do
      expect {
        described_class.new(provider_module: 'Test', required_attributes: {})
      }.to raise_error(ArgumentError, /resource_type/)
    end

    it 'raises without required_attributes' do
      expect {
        described_class.new(provider_module: 'Test', resource_type: 'test')
      }.to raise_error(ArgumentError, /required_attributes/)
    end
  end

  describe '#generate' do
    it 'produces valid Ruby spec code' do
      output = basic_generator.generate
      expect(output).to include("RSpec.describe 'aws_vpc'")
      expect(output).to include('synthesizes with valid attributes')
    end

    it 'includes reference test' do
      output = basic_generator.generate
      expect(output).to include('returns ResourceReference with correct outputs')
      expect(output).to include('${aws_vpc.test.id}')
    end

    it 'includes tags test when supports_tags is true' do
      output = full_generator.generate
      expect(output).to include('synthesizes with tags')
    end

    it 'includes terraform ref tests for specified fields' do
      output = full_generator.generate
      expect(output).to include('accepts Terraform references in role')
    end

    it 'includes mutually exclusive tests' do
      output = full_generator.generate
      expect(output).to include('rejects both name and name_prefix set simultaneously')
    end

    it 'omits tags test when supports_tags is false' do
      gen = described_class.new(
        provider_module: 'Test',
        resource_type: 'test_res',
        required_attributes: { name: 'test' },
        supports_tags: false,
      )
      output = gen.generate
      expect(output).not_to include('synthesizes with tags')
    end
  end

  describe 'format_hash' do
    it 'formats strings with escaped quotes' do
      gen = basic_generator
      result = gen.send(:format_hash, { key: "it's a value" })
      expect(result).to include("it\\'s a value")
    end

    it 'formats booleans' do
      gen = basic_generator
      result = gen.send(:format_hash, { enabled: true, disabled: false })
      expect(result).to include('enabled: true')
      expect(result).to include('disabled: false')
    end

    it 'formats integers and floats' do
      gen = basic_generator
      result = gen.send(:format_hash, { port: 443, ratio: 0.5 })
      expect(result).to include('port: 443')
      expect(result).to include('ratio: 0.5')
    end
  end

  describe 'HEADER constant' do
    it 'is frozen' do
      expect(described_class::HEADER).to be_frozen
    end

    it 'includes spec_helper require' do
      expect(described_class::HEADER).to include("require 'spec_helper'")
    end
  end
end
