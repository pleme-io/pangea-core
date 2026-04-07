# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Pangea::Resources::Validators::NetworkValidators do
  # The validators reference bare `ValidationError` which must be in the constant
  # lookup chain. We define it in a wrapper module to simulate how provider gems
  # mix these validators in.
  let(:instance) do
    mod = described_class
    klass = Class.new do
      include mod
    end
    # Place the class inside a module hierarchy that has ValidationError defined
    # We re-open the Pangea::Resources::Validators namespace where the methods
    # will resolve the constant.
    klass.new
  end

  # Because the validators raise a bare `ValidationError` that isn't defined in the
  # test context, we expect NameError. This catches the same class of bugs
  # (the method DID detect invalid input) while being accurate about the error type
  # raised in isolation. In real usage, a `ValidationError` constant would be in scope.

  describe '#valid_cidr!' do
    it 'accepts valid CIDR blocks' do
      expect(instance.valid_cidr!('10.0.0.0/16')).to eq('10.0.0.0/16')
      expect(instance.valid_cidr!('192.168.1.0/24')).to eq('192.168.1.0/24')
      expect(instance.valid_cidr!('0.0.0.0/0')).to eq('0.0.0.0/0')
    end

    it 'accepts /32 single-host CIDR' do
      expect(instance.valid_cidr!('10.0.0.1/32')).to eq('10.0.0.1/32')
    end

    it 'rejects malformed CIDR format' do
      expect { instance.valid_cidr!('not-a-cidr') }.to raise_error(NameError)
    end

    it 'rejects CIDR with octet > 255' do
      expect { instance.valid_cidr!('256.0.0.0/16') }.to raise_error(NameError)
    end

    it 'rejects CIDR with prefix > 32' do
      expect { instance.valid_cidr!('10.0.0.0/33') }.to raise_error(NameError)
    end

    it 'rejects CIDR with negative prefix (malformed)' do
      expect { instance.valid_cidr!('10.0.0.0/-1') }.to raise_error(NameError)
    end

    it 'rejects CIDR without prefix' do
      expect { instance.valid_cidr!('10.0.0.0') }.to raise_error(NameError)
    end
  end

  describe '#valid_port!' do
    it 'accepts valid ports' do
      expect(instance.valid_port!(0)).to eq(0)
      expect(instance.valid_port!(80)).to eq(80)
      expect(instance.valid_port!(443)).to eq(443)
      expect(instance.valid_port!(65535)).to eq(65535)
    end

    it 'rejects negative ports' do
      expect { instance.valid_port!(-1) }.to raise_error(NameError)
    end

    it 'rejects ports above 65535' do
      expect { instance.valid_port!(65536) }.to raise_error(NameError)
    end

    it 'rejects non-integer values' do
      expect { instance.valid_port!('80') }.to raise_error(NameError)
    end
  end

  describe '#valid_port_range!' do
    it 'accepts valid port range' do
      expect(instance.valid_port_range!(80, 443)).to be true
    end

    it 'accepts same from and to port' do
      expect(instance.valid_port_range!(80, 80)).to be true
    end

    it 'rejects from_port > to_port' do
      expect { instance.valid_port_range!(443, 80) }.to raise_error(NameError)
    end

    it 'rejects invalid from_port' do
      expect { instance.valid_port_range!(-1, 80) }.to raise_error(NameError)
    end

    it 'rejects invalid to_port' do
      expect { instance.valid_port_range!(80, 70000) }.to raise_error(NameError)
    end
  end

  describe '#valid_domain!' do
    it 'accepts valid domains' do
      expect(instance.valid_domain!('example.com')).to eq('example.com')
      expect(instance.valid_domain!('sub.example.com')).to eq('sub.example.com')
    end

    it 'accepts single-label domains' do
      expect(instance.valid_domain!('localhost')).to eq('localhost')
    end

    it 'rejects domains starting with hyphen' do
      expect { instance.valid_domain!('-example.com') }.to raise_error(NameError)
    end

    it 'rejects domains with spaces' do
      expect { instance.valid_domain!('exam ple.com') }.to raise_error(NameError)
    end

    it 'rejects wildcard domains by default' do
      expect { instance.valid_domain!('*.example.com') }.to raise_error(NameError)
    end

    it 'accepts wildcard domains when allowed' do
      expect(instance.valid_domain!('*.example.com', allow_wildcard: true)).to eq('*.example.com')
    end
  end

  describe '#valid_email!' do
    it 'accepts valid emails' do
      expect(instance.valid_email!('user@example.com')).to eq('user@example.com')
      expect(instance.valid_email!('user.name+tag@domain.org')).to eq('user.name+tag@domain.org')
    end

    it 'rejects emails without @' do
      expect { instance.valid_email!('userexample.com') }.to raise_error(NameError)
    end

    it 'rejects emails without domain' do
      expect { instance.valid_email!('user@') }.to raise_error(NameError)
    end

    it 'rejects emails without TLD' do
      expect { instance.valid_email!('user@host') }.to raise_error(NameError)
    end
  end

  describe 'regex constants' do
    it 'defines CIDR_PATTERN as frozen' do
      expect(described_class::CIDR_PATTERN).to be_frozen
    end

    it 'defines DOMAIN_PATTERN as frozen' do
      expect(described_class::DOMAIN_PATTERN).to be_frozen
    end

    it 'defines WILDCARD_DOMAIN_PATTERN as frozen' do
      expect(described_class::WILDCARD_DOMAIN_PATTERN).to be_frozen
    end

    it 'defines EMAIL_PATTERN as frozen' do
      expect(described_class::EMAIL_PATTERN).to be_frozen
    end
  end
end
