# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Pangea::Resources::Builders::OutputBuilder do
  describe 'initialization' do
    it 'stores resource type and name' do
      builder = described_class.new(:aws_vpc, 'main')
      expect(builder.resource_type).to eq(:aws_vpc)
      expect(builder.resource_name).to eq('main')
    end

    it 'accepts custom outputs' do
      builder = described_class.new(:aws_vpc, 'main', :cidr_block, :enable_dns)
      expect(builder.custom_outputs).to eq([:cidr_block, :enable_dns])
    end

    it 'flattens nested output arrays' do
      builder = described_class.new(:aws_vpc, 'main', [:cidr_block], [:enable_dns])
      expect(builder.custom_outputs).to eq([:cidr_block, :enable_dns])
    end
  end

  describe '#build' do
    it 'always includes :id' do
      builder = described_class.new(:unknown_type, 'test')
      outputs = builder.build
      expect(outputs).to have_key(:id)
    end

    it 'includes AWS common outputs for aws_ resources' do
      builder = described_class.new(:aws_vpc, 'main')
      outputs = builder.build
      expect(outputs).to have_key(:id)
      expect(outputs).to have_key(:arn)
    end

    it 'includes cloudflare common outputs for cloudflare_ resources' do
      builder = described_class.new(:cloudflare_zone, 'main')
      outputs = builder.build
      expect(outputs).to have_key(:id)
    end

    it 'includes custom outputs' do
      builder = described_class.new(:aws_vpc, 'main', :custom_attr)
      outputs = builder.build
      expect(outputs).to have_key(:custom_attr)
    end

    it 'generates interpolation strings as values' do
      builder = described_class.new(:aws_vpc, 'main')
      outputs = builder.build
      expect(outputs[:id]).to eq('${aws_vpc.main.id}')
    end
  end

  describe '#with_preset' do
    it 'includes preset outputs' do
      builder = described_class.new(:aws_vpc, 'main').with_preset
      outputs = builder.build
      expect(outputs).to have_key(:cidr_block)
      expect(outputs).to have_key(:default_security_group_id)
    end

    it 'accepts custom preset name' do
      builder = described_class.new(:custom_type, 'main').with_preset(:aws_s3_bucket)
      outputs = builder.build
      expect(outputs).to have_key(:bucket_domain_name)
    end

    it 'returns self for chaining' do
      builder = described_class.new(:aws_vpc, 'main')
      expect(builder.with_preset).to eq(builder)
    end
  end

  describe '#interpolation_string' do
    it 'generates terraform interpolation' do
      builder = described_class.new(:aws_vpc, 'main')
      expect(builder.interpolation_string(:id)).to eq('${aws_vpc.main.id}')
    end
  end

  describe '#id' do
    it 'returns id interpolation string' do
      builder = described_class.new(:aws_vpc, 'main')
      expect(builder.id).to eq('${aws_vpc.main.id}')
    end
  end

  describe '#arn' do
    it 'returns arn interpolation string' do
      builder = described_class.new(:aws_vpc, 'main')
      expect(builder.arn).to eq('${aws_vpc.main.arn}')
    end
  end

  describe 'provider detection' do
    it 'detects AWS provider' do
      builder = described_class.new(:aws_lambda_function, 'test')
      outputs = builder.build
      expect(outputs).to have_key(:arn)
    end

    it 'detects hcloud provider' do
      builder = described_class.new(:hcloud_server, 'test')
      outputs = builder.build
      expect(outputs).to have_key(:id)
    end

    it 'handles unknown provider gracefully' do
      builder = described_class.new(:custom_resource, 'test')
      outputs = builder.build
      expect(outputs).to have_key(:id)
      expect(outputs.size).to eq(1)
    end
  end

  describe 'OUTPUT_PRESETS' do
    it 'is frozen' do
      expect(described_class::OUTPUT_PRESETS).to be_frozen
    end

    it 'includes presets for common AWS resources' do
      expect(described_class::OUTPUT_PRESETS).to have_key(:aws_vpc)
      expect(described_class::OUTPUT_PRESETS).to have_key(:aws_subnet)
      expect(described_class::OUTPUT_PRESETS).to have_key(:aws_security_group)
      expect(described_class::OUTPUT_PRESETS).to have_key(:aws_iam_role)
    end

    it 'includes presets for cloudflare resources' do
      expect(described_class::OUTPUT_PRESETS).to have_key(:cloudflare_zone)
      expect(described_class::OUTPUT_PRESETS).to have_key(:cloudflare_record)
    end

    it 'includes presets for hcloud resources' do
      expect(described_class::OUTPUT_PRESETS).to have_key(:hcloud_server)
      expect(described_class::OUTPUT_PRESETS).to have_key(:hcloud_network)
    end
  end
end
