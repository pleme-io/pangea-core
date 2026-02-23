# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Pangea::Resources::Helpers do
  let(:helper_class) do
    Class.new { include Pangea::Resources::Helpers }
  end

  let(:helper) { helper_class.new }

  describe '#ref' do
    it 'creates terraform resource reference' do
      expect(helper.ref(:aws_vpc, :main, :id)).to eq('${aws_vpc.main.id}')
    end

    it 'works with string arguments' do
      expect(helper.ref('aws_subnet', 'public', 'cidr_block')).to eq('${aws_subnet.public.cidr_block}')
    end
  end

  describe '#data_ref' do
    it 'creates terraform data source reference' do
      expect(helper.data_ref(:aws_ami, :ubuntu, :id)).to eq('${data.aws_ami.ubuntu.id}')
    end

    it 'works with string arguments' do
      expect(helper.data_ref('aws_ami', 'latest', 'image_id')).to eq('${data.aws_ami.latest.image_id}')
    end
  end

  describe '#var' do
    it 'creates terraform variable reference' do
      expect(helper.var(:region)).to eq('${var.region}')
    end

    it 'works with string arguments' do
      expect(helper.var('instance_type')).to eq('${var.instance_type}')
    end
  end

  describe '#local' do
    it 'creates terraform local reference' do
      expect(helper.local(:common_tags)).to eq('${local.common_tags}')
    end

    it 'works with string arguments' do
      expect(helper.local('subnet_ids')).to eq('${local.subnet_ids}')
    end
  end
end
