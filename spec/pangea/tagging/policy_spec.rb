# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Pangea::Tagging::TaggingPolicy do
  describe '.default' do
    let(:policy) { described_class.default }

    it 'requires standard Pangea tags' do
      expect(policy.required_keys).to include('ManagedBy', 'Purpose', 'Environment', 'Team', 'PangeaFingerprint')
    end

    it 'passes for valid tags' do
      tags = {
        ManagedBy: 'pangea',
        Purpose: 'k3s-cluster',
        Environment: 'development',
        Team: 'platform',
        PangeaFingerprint: 'a1b2c3d4',
      }
      expect(policy.compliant?(tags)).to be true
    end

    it 'fails for missing required tags' do
      tags = { ManagedBy: 'pangea' }
      expect(policy.compliant?(tags)).to be false
      violations = policy.check(tags)
      expect(violations.length).to eq(4)
    end

    it 'fails for forbidden ManagedBy values' do
      tags = {
        ManagedBy: 'manual',
        Purpose: 'test',
        Environment: 'dev',
        Team: 'eng',
        PangeaFingerprint: 'abc',
      }
      violations = policy.check(tags)
      expect(violations).to include("Forbidden value 'manual' for tag 'ManagedBy'")
    end
  end

  describe '.strict' do
    let(:policy) { described_class.strict }

    it 'requires fingerprint full hash and architecture' do
      expect(policy.required_keys).to include('PangeaFingerprintFull', 'PangeaArchitecture')
    end
  end

  describe '#validate!' do
    let(:policy) { described_class.default }

    it 'raises TaggingViolation on missing tags' do
      expect { policy.validate!({}, resource_name: 'aws_vpc.main') }
        .to raise_error(Pangea::Tagging::TaggingViolation, /aws_vpc.main/)
    end

    it 'does not raise for compliant tags' do
      tags = {
        ManagedBy: 'pangea',
        Purpose: 'test',
        Environment: 'dev',
        Team: 'eng',
        PangeaFingerprint: 'abc',
      }
      expect { policy.validate!(tags) }.not_to raise_error
    end
  end
end
