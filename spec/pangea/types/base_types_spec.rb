# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Pangea::Types::BaseTypes do
  let(:registry) { Pangea::Types::Registry.instance }

  before(:all) do
    Pangea::Types::BaseTypes.register_all(Pangea::Types::Registry.instance)
  end

  describe 'cidr_block type' do
    it 'is registered' do
      typedef = registry[:cidr_block]
      expect(typedef.name).to eq(:cidr_block)
      expect(typedef.base_type).to eq(String)
    end

    it 'has format constraint' do
      typedef = registry[:cidr_block]
      expect(typedef.constraints[:format]).to be_a(Regexp)
    end

    it 'has validation' do
      typedef = registry[:cidr_block]
      expect(typedef.validations).not_to be_empty
    end
  end

  describe 'port type' do
    it 'is registered with Integer base' do
      typedef = registry[:port]
      expect(typedef.base_type).to eq(Integer)
    end

    it 'has range constraint 1-65535' do
      typedef = registry[:port]
      expect(typedef.constraints[:range]).to eq(1..65535)
    end
  end

  describe 'protocol type' do
    it 'is registered with String base' do
      typedef = registry[:protocol]
      expect(typedef.base_type).to eq(String)
    end

    it 'has enum constraint' do
      typedef = registry[:protocol]
      expect(typedef.constraints[:enum]).to eq(%w[tcp udp icmp all])
    end
  end

  describe 'ip_address type' do
    it 'is registered' do
      typedef = registry[:ip_address]
      expect(typedef.constraints[:format]).to be_a(Regexp)
    end
  end

  describe 'domain_name type' do
    it 'is registered with max_length 253' do
      typedef = registry[:domain_name]
      expect(typedef.constraints[:max_length]).to eq(253)
    end
  end
end
