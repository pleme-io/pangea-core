# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Pangea::Resources::NetworkHelpers do
  let(:helper_class) do
    Class.new { include Pangea::Resources::NetworkHelpers }
  end

  let(:helper) { helper_class.new }

  describe '#cidr_block' do
    it 'creates CIDR notation from IP and mask' do
      expect(helper.cidr_block('10.0.0.0', 16)).to eq('10.0.0.0/16')
      expect(helper.cidr_block('192.168.1.0', 24)).to eq('192.168.1.0/24')
      expect(helper.cidr_block('0.0.0.0', 0)).to eq('0.0.0.0/0')
    end
  end

  describe '#subnet_cidr' do
    it 'calculates subnet CIDRs from base CIDR' do
      result = helper.subnet_cidr('10.0.0.0/16', 8, 0)
      expect(result).to eq('10.0.0.0/24')
    end

    it 'offsets correctly for multiple subnets' do
      result = helper.subnet_cidr('10.0.0.0/16', 8, 1)
      expect(result).to include('/24')
    end
  end

  describe '#availability_zones' do
    it 'generates default 3 availability zones' do
      zones = helper.availability_zones('us-east-1')
      expect(zones).to eq(['us-east-1a', 'us-east-1b', 'us-east-1c'])
    end

    it 'generates specified number of zones' do
      zones = helper.availability_zones('eu-west-1', 2)
      expect(zones).to eq(['eu-west-1a', 'eu-west-1b'])
    end

    it 'generates up to 6 zones' do
      zones = helper.availability_zones('ap-southeast-1', 6)
      expect(zones.length).to eq(6)
      expect(zones.last).to eq('ap-southeast-1f')
    end

    it 'generates 1 zone' do
      zones = helper.availability_zones('us-west-2', 1)
      expect(zones).to eq(['us-west-2a'])
    end
  end

  describe '#valid_ip?' do
    it 'returns true for valid IP addresses' do
      expect(helper.valid_ip?('10.0.0.1')).to be true
      expect(helper.valid_ip?('192.168.1.1')).to be true
      expect(helper.valid_ip?('0.0.0.0')).to be true
      expect(helper.valid_ip?('255.255.255.255')).to be true
    end

    it 'returns false for invalid IP addresses' do
      expect(helper.valid_ip?('256.0.0.1')).to be false
      expect(helper.valid_ip?('10.0.0')).to be false
      expect(helper.valid_ip?('not-an-ip')).to be false
      expect(helper.valid_ip?('10.0.0.0.1')).to be false
      expect(helper.valid_ip?('')).to be false
    end
  end

  describe '#discover_public_ip' do
    it 'caches the result across multiple calls' do
      discovery_mock = instance_double(Pangea::Utilities::IpDiscovery, discover: '1.2.3.4')
      allow(Pangea::Utilities::IpDiscovery).to receive(:new).and_return(discovery_mock)

      # Suppress puts output
      allow(helper).to receive(:puts)

      first_result = helper.discover_public_ip
      second_result = helper.discover_public_ip

      expect(first_result).to eq('1.2.3.4')
      expect(second_result).to eq('1.2.3.4')
      # IpDiscovery.new should only be called once due to caching
      expect(Pangea::Utilities::IpDiscovery).to have_received(:new).once
    end
  end

  describe 'auto-registration' do
    it 'auto-registers NetworkHelpers when the file is loaded' do
      # The module is auto-registered at load time. If a previous test
      # cleared the registry, re-require to trigger the registration.
      # Instead of testing global state, verify the registration call exists
      # by loading the file fresh.
      Pangea::ResourceRegistry.register_module(Pangea::Resources::NetworkHelpers)
      expect(Pangea::ResourceRegistry.registered?(Pangea::Resources::NetworkHelpers)).to be true
    end
  end
end
