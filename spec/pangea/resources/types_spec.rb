# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Pangea::Resources::Types do
  let(:types) { Pangea::Resources::Types }

  describe 'CidrBlock' do
    it 'accepts valid CIDR blocks' do
      expect(types::CidrBlock['10.0.0.0/16']).to eq('10.0.0.0/16')
      expect(types::CidrBlock['192.168.1.0/24']).to eq('192.168.1.0/24')
      expect(types::CidrBlock['0.0.0.0/0']).to eq('0.0.0.0/0')
      expect(types::CidrBlock['172.16.0.0/12']).to eq('172.16.0.0/12')
    end

    it 'rejects invalid CIDR blocks' do
      expect { types::CidrBlock['not-a-cidr'] }.to raise_error(Dry::Types::ConstraintError)
      expect { types::CidrBlock['10.0.0.0'] }.to raise_error(Dry::Types::ConstraintError)
      expect { types::CidrBlock['10.0.0/16'] }.to raise_error(Dry::Types::ConstraintError)
    end
  end

  describe 'DomainName' do
    it 'accepts valid domain names' do
      expect(types::DomainName['example.com']).to eq('example.com')
      expect(types::DomainName['sub.example.com']).to eq('sub.example.com')
      expect(types::DomainName['a.b.c.example.com']).to eq('a.b.c.example.com')
    end

    it 'rejects invalid domain names' do
      expect { types::DomainName['-invalid.com'] }.to raise_error(Dry::Types::ConstraintError)
      expect { types::DomainName['invalid-.com'] }.to raise_error(Dry::Types::ConstraintError)
    end
  end

  describe 'WildcardDomainName' do
    it 'accepts valid wildcard domain names' do
      expect(types::WildcardDomainName['*.example.com']).to eq('*.example.com')
      expect(types::WildcardDomainName['*.sub.example.com']).to eq('*.sub.example.com')
    end

    it 'rejects invalid wildcard domain names' do
      expect { types::WildcardDomainName['example.com'] }.to raise_error(Dry::Types::ConstraintError)
      expect { types::WildcardDomainName['**.example.com'] }.to raise_error(Dry::Types::ConstraintError)
    end
  end

  describe 'EmailAddress' do
    it 'accepts valid email addresses' do
      expect(types::EmailAddress['user@example.com']).to eq('user@example.com')
      expect(types::EmailAddress['test.user+tag@domain.org']).to eq('test.user+tag@domain.org')
    end

    it 'rejects invalid email addresses' do
      expect { types::EmailAddress['not-an-email'] }.to raise_error(Dry::Types::ConstraintError)
      expect { types::EmailAddress['@domain.com'] }.to raise_error(Dry::Types::ConstraintError)
    end
  end

  describe 'Port' do
    it 'accepts valid ports' do
      expect(types::Port[0]).to eq(0)
      expect(types::Port[80]).to eq(80)
      expect(types::Port[443]).to eq(443)
      expect(types::Port[65535]).to eq(65535)
    end

    it 'rejects invalid ports' do
      expect { types::Port[-1] }.to raise_error(Dry::Types::ConstraintError)
      expect { types::Port[65536] }.to raise_error(Dry::Types::ConstraintError)
    end
  end

  describe 'IpProtocol' do
    it 'accepts valid protocols' do
      %w[tcp udp icmp icmpv6 all -1].each do |proto|
        expect(types::IpProtocol[proto]).to eq(proto)
      end
    end

    it 'rejects invalid protocols' do
      expect { types::IpProtocol['http'] }.to raise_error(Dry::Types::ConstraintError)
      expect { types::IpProtocol['ftp'] }.to raise_error(Dry::Types::ConstraintError)
    end
  end

  describe 'PortRange' do
    it 'accepts valid port ranges' do
      result = types::PortRange[from_port: 80, to_port: 443]
      expect(result[:from_port]).to eq(80)
      expect(result[:to_port]).to eq(443)
    end
  end

  describe 'PosixPermissions' do
    it 'accepts valid permission strings' do
      expect(types::PosixPermissions['644']).to eq('644')
      expect(types::PosixPermissions['0755']).to eq('0755')
      expect(types::PosixPermissions['777']).to eq('777')
    end

    it 'rejects invalid permission strings' do
      expect { types::PosixPermissions['89'] }.to raise_error(Dry::Types::ConstraintError)
      expect { types::PosixPermissions['12345'] }.to raise_error(Dry::Types::ConstraintError)
    end
  end

  describe 'UnixUserId' do
    it 'accepts valid user IDs' do
      expect(types::UnixUserId[0]).to eq(0)
      expect(types::UnixUserId[1000]).to eq(1000)
      expect(types::UnixUserId[4294967295]).to eq(4294967295)
    end

    it 'rejects invalid user IDs' do
      expect { types::UnixUserId[-1] }.to raise_error(Dry::Types::ConstraintError)
    end
  end

  describe 'UnixGroupId' do
    it 'accepts valid group IDs' do
      expect(types::UnixGroupId[0]).to eq(0)
      expect(types::UnixGroupId[1000]).to eq(1000)
    end

    it 'rejects invalid group IDs' do
      expect { types::UnixGroupId[-1] }.to raise_error(Dry::Types::ConstraintError)
    end
  end

  describe '.register_provider_types' do
    after { Pangea::Resources::Types.instance_variable_set(:@provider_type_modules, []) }

    it 'registers a provider type module' do
      test_mod = Module.new do
        TestType = Dry::Types['strict.string']
      end
      types.register_provider_types(test_mod)
      expect(types.instance_variable_get(:@provider_type_modules)).to include(test_mod)
    end

    it 'does not register the same module twice' do
      test_mod = Module.new
      types.register_provider_types(test_mod)
      types.register_provider_types(test_mod)
      expect(types.instance_variable_get(:@provider_type_modules).count(test_mod)).to eq(1)
    end
  end

  describe '.const_missing' do
    it 'resolves ResourceReference' do
      expect(types::ResourceReference).to eq(Pangea::Resources::ResourceReference)
    end

    it 'raises NameError for unknown constants with no provider modules' do
      expect { types::NonExistentType123 }.to raise_error(NameError)
    end
  end
end
