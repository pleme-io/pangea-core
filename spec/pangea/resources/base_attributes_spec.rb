# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Pangea::Resources::BaseAttributes do
  # Create a test subclass to exercise BaseAttributes functionality
  let(:test_class) do
    Class.new(described_class) do
      attribute :name, Pangea::Resources::Types::String
      attribute :count, Pangea::Resources::Types::Integer.default(1)
      attribute :enabled, Pangea::Resources::Types::Bool.default(true)
    end
  end

  describe 'T constant' do
    it 'aliases Pangea::Resources::Types' do
      expect(described_class::T).to eq(Pangea::Resources::Types)
    end
  end

  describe 'transform_keys' do
    it 'normalizes string keys to symbols' do
      instance = test_class.new('name' => 'test', 'count' => 5)
      expect(instance.name).to eq('test')
      expect(instance.count).to eq(5)
    end

    it 'accepts symbol keys directly' do
      instance = test_class.new(name: 'test', count: 5)
      expect(instance.name).to eq('test')
      expect(instance.count).to eq(5)
    end
  end

  describe 'TERRAFORM_REF_PATTERN' do
    it 'matches terraform interpolation syntax' do
      expect('${aws_vpc.main.id}').to match(described_class::TERRAFORM_REF_PATTERN)
      expect('${data.aws_ami.ubuntu.id}').to match(described_class::TERRAFORM_REF_PATTERN)
    end

    it 'does not match non-terraform strings' do
      expect('plain string').not_to match(described_class::TERRAFORM_REF_PATTERN)
      expect('$no_braces').not_to match(described_class::TERRAFORM_REF_PATTERN)
    end
  end

  describe '.terraform_reference?' do
    it 'returns true for terraform references' do
      expect(described_class.terraform_reference?('${aws_vpc.main.id}')).to be true
      expect(described_class.terraform_reference?('prefix ${var.name} suffix')).to be true
    end

    it 'returns false for non-terraform strings' do
      expect(described_class.terraform_reference?('plain string')).to be false
    end

    it 'returns false for non-string values' do
      expect(described_class.terraform_reference?(42)).to be false
      expect(described_class.terraform_reference?(nil)).to be false
      expect(described_class.terraform_reference?(true)).to be false
    end
  end

  describe '#terraform_reference?' do
    it 'delegates to class method' do
      instance = test_class.new(name: 'test')
      expect(instance.terraform_reference?('${aws_vpc.main.id}')).to be true
      expect(instance.terraform_reference?('plain')).to be false
    end
  end

  describe '#copy_with' do
    it 'creates a copy with merged attributes' do
      instance = test_class.new(name: 'original', count: 1)
      copy = instance.copy_with(name: 'modified')
      expect(copy.name).to eq('modified')
      expect(copy.count).to eq(1)
    end

    it 'preserves original instance' do
      instance = test_class.new(name: 'original', count: 1)
      instance.copy_with(name: 'modified')
      expect(instance.name).to eq('original')
    end

    it 'accepts string keys via transform_keys' do
      instance = test_class.new(name: 'original')
      copy = instance.copy_with('name' => 'modified')
      expect(copy.name).to eq('modified')
    end

    it 'merges multiple attributes' do
      instance = test_class.new(name: 'original', count: 1, enabled: true)
      copy = instance.copy_with(name: 'new', count: 99, enabled: false)
      expect(copy.name).to eq('new')
      expect(copy.count).to eq(99)
      expect(copy.enabled).to be false
    end
  end

  describe 'default values' do
    it 'uses default values when attributes are omitted' do
      instance = test_class.new(name: 'test')
      expect(instance.count).to eq(1)
      expect(instance.enabled).to be true
    end
  end
end
