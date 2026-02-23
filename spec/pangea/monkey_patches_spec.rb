# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'ActiveSupport-like monkey patches' do
  describe 'Object#present?' do
    it 'returns true for non-nil, non-empty objects' do
      expect(42.present?).to be true
      expect([1].present?).to be true
      expect({ a: 1 }.present?).to be true
      expect(:symbol.present?).to be true
    end

    it 'returns false for empty objects' do
      expect([].present?).to be false
      expect({}.present?).to be false
    end
  end

  describe 'Object#blank?' do
    it 'returns false for non-nil, non-empty objects' do
      expect(42.blank?).to be_falsey
      expect([1].blank?).to be false
      expect({ a: 1 }.blank?).to be false
    end

    it 'returns true for empty objects' do
      expect([].blank?).to be true
      expect({}.blank?).to be true
    end
  end

  describe 'NilClass' do
    it '#present? returns false' do
      expect(nil.present?).to be false
    end

    it '#blank? returns true' do
      expect(nil.blank?).to be true
    end
  end

  describe 'FalseClass' do
    it '#present? returns false' do
      expect(false.present?).to be false
    end

    it '#blank? returns true' do
      expect(false.blank?).to be true
    end
  end

  describe 'TrueClass' do
    it '#present? returns true' do
      expect(true.present?).to be true
    end

    it '#blank? returns false' do
      expect(true.blank?).to be false
    end
  end

  describe 'String' do
    it '#present? returns true for non-empty strings' do
      expect('hello'.present?).to be true
      expect(' '.present?).to be true
    end

    it '#present? returns false for empty strings' do
      expect(''.present?).to be false
    end

    it '#blank? returns true for empty strings' do
      expect(''.blank?).to be true
    end

    it '#blank? returns true for whitespace-only strings' do
      expect('   '.blank?).to be true
      expect("\t\n".blank?).to be true
    end

    it '#blank? returns false for non-empty strings' do
      expect('hello'.blank?).to be false
    end
  end
end
