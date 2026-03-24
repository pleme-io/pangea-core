# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Pangea::Contracts::IamResult do
  let(:result) { described_class.new }

  let(:role_ref) { double('role_ref', id: 'role-123') }
  let(:profile_ref) { double('profile_ref', id: 'profile-456') }

  describe 'attr_accessors' do
    it 'starts with nil values' do
      expect(result.role).to be_nil
      expect(result.instance_profile).to be_nil
      expect(result.policies).to eq({})
    end

    it 'can set role and instance_profile' do
      result.role = role_ref
      result.instance_profile = profile_ref
      expect(result.role).to eq(role_ref)
      expect(result.instance_profile).to eq(profile_ref)
    end
  end

  describe '#[]' do
    before do
      result.role = role_ref
      result.instance_profile = profile_ref
      result.policies[:ecr_policy] = double('ecr', id: 'ecr-1')
    end

    it 'accesses role by key' do
      expect(result[:role]).to eq(role_ref)
    end

    it 'accesses instance_profile by key' do
      expect(result[:instance_profile]).to eq(profile_ref)
    end

    it 'accesses named policies by key' do
      expect(result[:ecr_policy]).not_to be_nil
      expect(result[:ecr_policy].id).to eq('ecr-1')
    end

    it 'returns nil for unknown keys' do
      expect(result[:nonexistent]).to be_nil
    end
  end

  describe '#to_h' do
    it 'includes only non-nil values' do
      result.role = role_ref
      hash = result.to_h
      expect(hash).to have_key(:role)
      expect(hash).not_to have_key(:instance_profile)
    end

    it 'includes policies in the hash' do
      ecr = double('ecr', id: 'ecr-1')
      result.policies[:ecr_policy] = ecr
      hash = result.to_h
      expect(hash[:ecr_policy]).to eq(ecr)
    end
  end

  describe '#key? / #has_key? / #include?' do
    before { result.role = role_ref }

    it 'returns true for present keys' do
      expect(result.key?(:role)).to be true
    end

    it 'returns false for missing keys' do
      expect(result.key?(:instance_profile)).to be false
    end
  end

  describe '#dig' do
    it 'delegates to to_h.dig' do
      result.role = role_ref
      expect(result.dig(:role)).to eq(role_ref)
    end
  end

  describe '#validate!' do
    it 'does not raise (no required fields)' do
      expect { result.validate! }.not_to raise_error
    end
  end
end
