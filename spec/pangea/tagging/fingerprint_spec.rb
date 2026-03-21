# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Pangea::Tagging::Fingerprint do
  let(:config) do
    {
      cluster_name: 'zek-dev',
      account_id: '123456789012',
      region: 'us-east-1',
      architecture: 'k3s_dev_cluster',
      version: '1.0.0',
    }
  end

  let(:fingerprint) { described_class.new(**config) }

  describe '#hex' do
    it 'returns a 64-character hex string' do
      expect(fingerprint.hex).to match(/\A[a-f0-9]{64}\z/)
    end

    it 'is deterministic' do
      fp1 = described_class.new(**config)
      fp2 = described_class.new(**config)
      expect(fp1.hex).to eq(fp2.hex)
    end

    it 'changes when config changes' do
      fp1 = described_class.new(**config)
      fp2 = described_class.new(**config.merge(cluster_name: 'different'))
      expect(fp1.hex).not_to eq(fp2.hex)
    end

    it 'is independent of key insertion order' do
      fp1 = described_class.new(a: 1, b: 2, c: 3)
      fp2 = described_class.new(c: 3, a: 1, b: 2)
      expect(fp1.hex).to eq(fp2.hex)
    end
  end

  describe '#short' do
    it 'returns first 8 characters of hex' do
      expect(fingerprint.short).to eq(fingerprint.hex[0, 8])
      expect(fingerprint.short.length).to eq(8)
    end
  end

  describe '#tags' do
    it 'includes base tags' do
      tags = fingerprint.tags
      expect(tags[:ManagedBy]).to eq('pangea')
      expect(tags[:Purpose]).to eq('infrastructure')
      expect(tags[:Environment]).to eq('development')
      expect(tags[:Team]).to eq('platform')
      expect(tags[:Cluster]).to eq('zek-dev')
    end

    it 'includes fingerprint tags' do
      tags = fingerprint.tags
      expect(tags[:PangeaFingerprint]).to eq(fingerprint.short)
      expect(tags[:PangeaFingerprintFull]).to eq(fingerprint.hex)
      expect(tags[:PangeaArchitecture]).to eq('k3s_dev_cluster')
      expect(tags[:PangeaVersion]).to eq('1.0.0')
    end

    it 'merges extra tags' do
      tags = fingerprint.tags(CostCenter: 'engineering')
      expect(tags[:CostCenter]).to eq('engineering')
      expect(tags[:PangeaFingerprint]).to eq(fingerprint.short)
    end
  end

  describe '#verify?' do
    it 'returns true for matching tags' do
      tags = fingerprint.tags
      expect(fingerprint.verify?(tags)).to be true
    end

    it 'returns false for non-matching tags' do
      expect(fingerprint.verify?({ PangeaFingerprint: 'wrong123' })).to be false
    end

    it 'returns false for missing tag' do
      expect(fingerprint.verify?({})).to be false
    end
  end

  describe '#verify_full?' do
    it 'returns true for matching full hash' do
      tags = fingerprint.tags
      expect(fingerprint.verify_full?(tags)).to be true
    end

    it 'returns false for short-only match' do
      expect(fingerprint.verify_full?({ PangeaFingerprint: fingerprint.short })).to be false
    end
  end

  describe '#verification_report' do
    it 'reports verified resources' do
      resources = {
        'aws_vpc.main' => fingerprint.tags,
        'aws_subnet.public' => fingerprint.tags,
        'aws_instance.rogue' => { PangeaFingerprint: 'wrong123' },
      }
      report = fingerprint.verification_report(resources)
      expect(report[:total]).to eq(3)
      expect(report[:verified]).to eq(2)
      expect(report[:failed].length).to eq(1)
      expect(report[:failed].first[:resource]).to eq('aws_instance.rogue')
    end
  end

  describe '#==' do
    it 'equals fingerprints with same config' do
      fp1 = described_class.new(**config)
      fp2 = described_class.new(**config)
      expect(fp1).to eq(fp2)
    end

    it 'differs from fingerprints with different config' do
      fp1 = described_class.new(**config)
      fp2 = described_class.new(**config.merge(version: '2.0.0'))
      expect(fp1).not_to eq(fp2)
    end
  end
end
