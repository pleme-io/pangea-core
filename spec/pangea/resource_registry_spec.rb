# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Pangea::ResourceRegistry do
  # Save and restore state around each test
  let(:original_modules) { described_class.registered_modules.dup }
  let(:original_provider_modules) do
    # Deep copy the provider modules hash
    described_class.instance_variable_get(:@provider_modules).each_with_object({}) do |(k, v), h|
      h[k] = v.dup
    end
  end

  before do
    # Capture state before the test
    @saved_modules = described_class.registered_modules.dup
    @saved_provider_modules = described_class.instance_variable_get(:@provider_modules).each_with_object({}) do |(k, v), h|
      h[k] = v.dup
    end
  end

  after do
    described_class.clear!
    # Restore provider modules
    pm = described_class.instance_variable_get(:@provider_modules)
    pm.clear
    @saved_provider_modules.each { |k, v| pm[k] = v }
    # Restore global modules
    @saved_modules.each { |m| described_class.register_module(m) }
  end

  describe '.register_module' do
    it 'registers a module' do
      test_mod = Module.new
      described_class.register_module(test_mod)
      expect(described_class.registered?(test_mod)).to be true
    end

    it 'does not duplicate registrations' do
      test_mod = Module.new
      described_class.register_module(test_mod)
      described_class.register_module(test_mod)
      count = described_class.registered_modules.count { |m| m == test_mod }
      expect(count).to eq(1)
    end
  end

  describe '.registered_modules' do
    it 'returns an array of registered modules' do
      expect(described_class.registered_modules).to be_an(Array)
    end
  end

  describe '.clear!' do
    it 'removes all registered modules' do
      described_class.register_module(Module.new)
      described_class.clear!
      expect(described_class.registered_modules).to be_empty
    end
  end

  describe '.registered?' do
    it 'returns true for registered modules' do
      test_mod = Module.new
      described_class.register_module(test_mod)
      expect(described_class.registered?(test_mod)).to be true
    end

    it 'returns false for unregistered modules' do
      expect(described_class.registered?(Module.new)).to be false
    end
  end

  describe '.register' do
    it 'registers module under a provider' do
      test_mod = Module.new
      described_class.register(:aws, test_mod)
      expect(described_class.modules_for(:aws)).to include(test_mod)
    end

    it 'also registers in global registry for backward compatibility' do
      test_mod = Module.new
      described_class.register(:hcloud, test_mod)
      expect(described_class.registered?(test_mod)).to be true
    end

    it 'does not duplicate provider registrations' do
      test_mod = Module.new
      described_class.register(:aws, test_mod)
      described_class.register(:aws, test_mod)
      expect(described_class.modules_for(:aws).count { |m| m == test_mod }).to eq(1)
    end
  end

  describe '.modules_for' do
    it 'returns modules for a specific provider' do
      mod_a = Module.new
      mod_b = Module.new
      described_class.register(:aws, mod_a)
      described_class.register(:aws, mod_b)
      expect(described_class.modules_for(:aws)).to contain_exactly(mod_a, mod_b)
    end

    it 'returns empty array for unknown provider' do
      expect(described_class.modules_for(:unknown_provider_xyz)).to eq([])
    end
  end

  describe '.stats' do
    it 'returns statistics hash' do
      stats = described_class.stats
      expect(stats).to be_a(Hash)
      expect(stats).to have_key(:total_modules)
      expect(stats).to have_key(:modules)
      expect(stats).to have_key(:by_provider)
    end

    it 'reflects registered modules count' do
      described_class.clear!
      mod1 = Module.new
      mod2 = Module.new
      described_class.register(:aws, mod1)
      described_class.register(:gcp, mod2)
      stats = described_class.stats
      expect(stats[:total_modules]).to eq(2)
      expect(stats[:by_provider]).to include(aws: 1, gcp: 1)
    end
  end
end
