# frozen_string_literal: true

require 'spec_helper'
require 'pangea/utilities/ip_discovery'

RSpec.describe Pangea::Utilities::IpDiscovery do
  let(:logger) { instance_double(Logger, info: nil, warn: nil) }
  let(:discovery) { described_class.new(timeout: 2, logger: logger) }

  describe '#initialize' do
    it 'sets timeout' do
      d = described_class.new(timeout: 10)
      expect(d.timeout).to eq(10)
    end

    it 'defaults timeout to 5' do
      d = described_class.new
      expect(d.timeout).to eq(5)
    end

    it 'accepts a custom logger' do
      d = described_class.new(logger: logger)
      expect(d.logger).to eq(logger)
    end
  end

  describe 'SERVICES' do
    it 'defines multiple IP discovery services' do
      expect(described_class::SERVICES).to be_an(Array)
      expect(described_class::SERVICES.length).to be >= 3
    end

    it 'each service has name, url, and parser' do
      described_class::SERVICES.each do |service|
        expect(service).to have_key(:name)
        expect(service).to have_key(:url)
        expect(service).to have_key(:parser)
        expect(service[:parser]).to respond_to(:call)
      end
    end
  end

  describe 'IP_REGEX' do
    it 'matches valid IP addresses' do
      expect('1.2.3.4').to match(described_class::IP_REGEX)
      expect('192.168.1.1').to match(described_class::IP_REGEX)
      expect('255.255.255.255').to match(described_class::IP_REGEX)
    end

    it 'does not match invalid formats' do
      expect('1.2.3').not_to match(described_class::IP_REGEX)
      expect('abc.def.ghi.jkl').not_to match(described_class::IP_REGEX)
      expect('1.2.3.4.5').not_to match(described_class::IP_REGEX)
    end
  end

  describe '#try_service' do
    let(:ipify_service) { described_class::SERVICES.find { |s| s[:name] == 'ipify' } }

    it 'returns IP on successful HTTP response' do
      response = instance_double(Net::HTTPOK, body: '{"ip":"1.2.3.4"}')
      allow(response).to receive(:is_a?).with(Net::HTTPSuccess).and_return(true)
      allow(Net::HTTP).to receive(:get_response).and_return(response)

      result = discovery.try_service(ipify_service)
      expect(result).to eq('1.2.3.4')
    end

    it 'returns nil on HTTP error' do
      response = instance_double(Net::HTTPServerError, code: '500')
      allow(response).to receive(:is_a?).with(Net::HTTPSuccess).and_return(false)
      allow(Net::HTTP).to receive(:get_response).and_return(response)

      result = discovery.try_service(ipify_service)
      expect(result).to be_nil
    end

    it 'returns nil on timeout' do
      allow(Timeout).to receive(:timeout).and_raise(Timeout::Error)

      result = discovery.try_service(ipify_service)
      expect(result).to be_nil
    end

    it 'returns nil on network error' do
      allow(Net::HTTP).to receive(:get_response).and_raise(SocketError.new('connection failed'))

      result = discovery.try_service(ipify_service)
      expect(result).to be_nil
    end

    it 'returns nil when response has invalid IP format' do
      response = instance_double(Net::HTTPOK, body: '{"ip":"not-an-ip"}')
      allow(response).to receive(:is_a?).with(Net::HTTPSuccess).and_return(true)
      allow(Net::HTTP).to receive(:get_response).and_return(response)

      result = discovery.try_service(ipify_service)
      expect(result).to be_nil
    end
  end

  describe '#discover' do
    it 'returns IP from first successful service' do
      response = instance_double(Net::HTTPOK, body: '{"ip":"5.6.7.8"}')
      allow(response).to receive(:is_a?).with(Net::HTTPSuccess).and_return(true)
      allow(Net::HTTP).to receive(:get_response).and_return(response)

      result = discovery.discover
      expect(result).to eq('5.6.7.8')
    end

    it 'raises DiscoveryError when all services fail' do
      allow(Net::HTTP).to receive(:get_response).and_raise(SocketError.new('no network'))

      expect { discovery.discover }.to raise_error(
        Pangea::Utilities::DiscoveryError,
        /Failed to discover public IP/
      )
    end
  end

  describe 'service parsers' do
    it 'ipify parser extracts IP from JSON' do
      service = described_class::SERVICES.find { |s| s[:name] == 'ipify' }
      expect(service[:parser].call('{"ip":"1.2.3.4"}')).to eq('1.2.3.4')
    end

    it 'ipinfo parser strips whitespace' do
      service = described_class::SERVICES.find { |s| s[:name] == 'ipinfo' }
      expect(service[:parser].call("1.2.3.4\n")).to eq('1.2.3.4')
    end

    it 'aws_checkip parser strips whitespace' do
      service = described_class::SERVICES.find { |s| s[:name] == 'aws_checkip' }
      expect(service[:parser].call("5.6.7.8\n")).to eq('5.6.7.8')
    end

    it 'ifconfig_me parser strips whitespace' do
      service = described_class::SERVICES.find { |s| s[:name] == 'ifconfig_me' }
      expect(service[:parser].call(" 9.10.11.12 \n")).to eq('9.10.11.12')
    end
  end
end
