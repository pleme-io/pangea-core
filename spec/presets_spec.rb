# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Pangea::Presets do
  let(:profiles) do
    {
      dev: { encryption: 'AES256', versioning: false, volume_size: 20 }.freeze,
      production: { encryption: 'aws:kms', versioning: true, volume_size: 100 }.freeze,
    }.freeze
  end

  describe '.apply' do
    it 'applies named profile defaults' do
      result = described_class.apply({ profile: :dev, bucket: 'my-bucket' }, profiles)
      expect(result[:encryption]).to eq('AES256')
      expect(result[:versioning]).to eq(false)
      expect(result[:bucket]).to eq('my-bucket')
    end

    it 'user config overrides profile defaults' do
      result = described_class.apply({ profile: :dev, encryption: 'aws:kms' }, profiles)
      expect(result[:encryption]).to eq('aws:kms')
    end

    it 'uses default_profile when none specified' do
      result = described_class.apply({ bucket: 'x' }, profiles, default_profile: :production)
      expect(result[:encryption]).to eq('aws:kms')
      expect(result[:versioning]).to eq(true)
    end

    it 'defaults to :dev profile' do
      result = described_class.apply({}, profiles)
      expect(result[:encryption]).to eq('AES256')
    end

    it 'strips :profile key from returned config' do
      result = described_class.apply({ profile: :dev }, profiles)
      expect(result).not_to have_key(:profile)
    end

    it 'raises on unknown profile' do
      expect { described_class.apply({ profile: :nonexistent }, profiles) }
        .to raise_error(ArgumentError, /Unknown profile :nonexistent/)
    end

    it 'does not mutate original config' do
      original = { profile: :dev, bucket: 'x' }
      original_copy = original.dup
      described_class.apply(original, profiles)
      expect(original).to eq(original_copy)
    end
  end

  describe '.compose' do
    it 'merges multiple presets left-to-right' do
      a = { encryption: 'AES256', versioning: false }
      b = { versioning: true, retention: 30 }
      result = described_class.compose(a, b)
      expect(result).to eq({ encryption: 'AES256', versioning: true, retention: 30 })
    end

    it 'returns frozen hash' do
      result = described_class.compose({ a: 1 }, { b: 2 })
      expect(result).to be_frozen
    end

    it 'deep merges nested hashes' do
      a = { tags: { ManagedBy: 'pangea' } }
      b = { tags: { Environment: 'dev' } }
      result = described_class.compose(a, b)
      expect(result[:tags]).to eq({ ManagedBy: 'pangea', Environment: 'dev' })
    end
  end

  describe '.deep_merge' do
    it 'overlay wins for scalar values' do
      expect(described_class.deep_merge({ a: 1 }, { a: 2 })).to eq({ a: 2 })
    end

    it 'recursively merges nested hashes' do
      base = { outer: { a: 1, b: 2 } }
      overlay = { outer: { b: 3, c: 4 } }
      expect(described_class.deep_merge(base, overlay)).to eq({ outer: { a: 1, b: 3, c: 4 } })
    end

    it 'overlay non-hash replaces base hash' do
      expect(described_class.deep_merge({ a: { b: 1 } }, { a: 'flat' })).to eq({ a: 'flat' })
    end

    it 'adds keys from overlay not in base' do
      expect(described_class.deep_merge({ a: 1 }, { b: 2 })).to eq({ a: 1, b: 2 })
    end
  end
end
