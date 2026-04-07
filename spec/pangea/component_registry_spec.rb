# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Pangea::ComponentRegistry do
  after do
    described_class.clear!
  end

  describe '.register_component' do
    it 'registers a component module' do
      mod = Module.new
      described_class.register_component(mod)
      expect(described_class.registered?(mod)).to be true
    end

    it 'does not duplicate registrations' do
      mod = Module.new
      described_class.register_component(mod)
      described_class.register_component(mod)
      expect(described_class.registered_components.count { |m| m == mod }).to eq(1)
    end

    it 'registers multiple distinct components' do
      mod1 = Module.new
      mod2 = Module.new
      described_class.register_component(mod1)
      described_class.register_component(mod2)
      expect(described_class.registered_components).to include(mod1, mod2)
    end
  end

  describe '.registered_components' do
    it 'returns a copy of the components array' do
      mod = Module.new
      described_class.register_component(mod)
      components = described_class.registered_components
      components.clear
      expect(described_class.registered_components).to include(mod)
    end
  end

  describe '.clear!' do
    it 'removes all registered components' do
      described_class.register_component(Module.new)
      described_class.register_component(Module.new)
      described_class.clear!
      expect(described_class.registered_components).to be_empty
    end
  end

  describe '.registered?' do
    it 'returns true for registered components' do
      mod = Module.new
      described_class.register_component(mod)
      expect(described_class.registered?(mod)).to be true
    end

    it 'returns false for unregistered components' do
      expect(described_class.registered?(Module.new)).to be false
    end
  end

  describe 'thread safety' do
    it 'handles concurrent registrations without errors' do
      modules = 20.times.map { Module.new }
      threads = modules.map do |mod|
        Thread.new { described_class.register_component(mod) }
      end
      threads.each(&:join)
      expect(described_class.registered_components.size).to eq(20)
    end
  end
end
