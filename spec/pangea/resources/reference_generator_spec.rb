# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Pangea::Resources::ReferenceGenerator do
  let(:klass) do
    Class.new do
      include Pangea::Resources::ReferenceGenerator
    end
  end

  let(:instance) { klass.new }

  describe '#terraform_ref' do
    it 'generates resource reference string' do
      expect(instance.terraform_ref('aws_vpc', 'main', 'id')).to eq('${aws_vpc.main.id}')
    end

    it 'handles symbol arguments' do
      expect(instance.terraform_ref(:aws_subnet, :private, :cidr_block)).to eq('${aws_subnet.private.cidr_block}')
    end
  end

  describe '#data_ref' do
    it 'generates data source reference string' do
      expect(instance.data_ref('aws_ami', 'ubuntu', 'id')).to eq('${data.aws_ami.ubuntu.id}')
    end

    it 'handles symbol arguments' do
      expect(instance.data_ref(:aws_caller_identity, :current, :account_id)).to eq('${data.aws_caller_identity.current.account_id}')
    end
  end

  describe 'RESOURCE_REF lambda' do
    it 'is frozen' do
      expect(described_class::RESOURCE_REF).to be_frozen
    end

    it 'generates correct format' do
      expect(described_class::RESOURCE_REF.call('aws_vpc', 'main', 'id')).to eq('${aws_vpc.main.id}')
    end
  end

  describe 'DATA_REF lambda' do
    it 'is frozen' do
      expect(described_class::DATA_REF).to be_frozen
    end

    it 'generates correct format' do
      expect(described_class::DATA_REF.call('aws_ami', 'ubuntu', 'id')).to eq('${data.aws_ami.ubuntu.id}')
    end
  end
end
