# frozen_string_literal: true

require 'spec_helper'
require 'pangea/testing'

RSpec.describe Pangea::Testing::IndifferentHash do
  describe '#[]' do
    it 'accesses string keys with string access' do
      h = described_class.new
      h['foo'] = 'bar'
      expect(h['foo']).to eq('bar')
    end

    it 'accesses string keys with symbol access' do
      h = described_class.new
      h['foo'] = 'bar'
      expect(h[:foo]).to eq('bar')
    end

    it 'accesses symbol keys with symbol access' do
      h = described_class.new
      h[:foo] = 'baz'
      expect(h[:foo]).to eq('baz')
    end

    it 'accesses symbol keys with string access' do
      h = described_class.new
      h[:foo] = 'baz'
      expect(h['foo']).to eq('baz')
    end

    it 'returns nil for missing keys' do
      h = described_class.new
      expect(h['missing']).to be_nil
      expect(h[:missing]).to be_nil
    end

    it 'prefers string key when both exist' do
      h = described_class.new
      h['foo'] = 'string_val'
      h[:foo] = 'symbol_val'
      expect(h['foo']).to eq('string_val')
    end
  end

  describe '#dig' do
    it 'digs into nested hashes' do
      h = described_class.deep_convert({ 'a' => { 'b' => 'c' } })
      expect(h.dig(:a, :b)).to eq('c')
      expect(h.dig('a', 'b')).to eq('c')
    end

    it 'returns nil for missing nested keys' do
      h = described_class.deep_convert({ 'a' => { 'b' => 'c' } })
      expect(h.dig(:a, :x)).to be_nil
      expect(h.dig(:x, :y)).to be_nil
    end

    it 'returns value for single key dig' do
      h = described_class.new
      h['foo'] = 'bar'
      expect(h.dig(:foo)).to eq('bar')
    end

    it 'returns nil when intermediate value is not diggable' do
      h = described_class.new
      h['foo'] = 'bar'
      expect(h.dig(:foo, :baz)).to be_nil
    end
  end

  describe '#has_key? / #key? / #include?' do
    let(:h) do
      result = described_class.new
      result['foo'] = 'bar'
      result
    end

    it 'finds string keys with string access' do
      expect(h.has_key?('foo')).to be true
    end

    it 'finds string keys with symbol access' do
      expect(h.has_key?(:foo)).to be true
    end

    it 'returns false for missing keys' do
      expect(h.has_key?(:missing)).to be false
    end

    it 'key? is aliased to has_key?' do
      expect(h.key?(:foo)).to be true
      expect(h.key?(:missing)).to be false
    end

    it 'include? is aliased to has_key?' do
      expect(h.include?(:foo)).to be true
      expect(h.include?(:missing)).to be false
    end
  end

  describe '#fetch' do
    let(:h) do
      result = described_class.new
      result['foo'] = 'bar'
      result
    end

    it 'fetches existing key with string' do
      expect(h.fetch('foo')).to eq('bar')
    end

    it 'fetches existing key with symbol' do
      expect(h.fetch(:foo)).to eq('bar')
    end

    it 'returns default value for missing key' do
      expect(h.fetch(:missing, 'default')).to eq('default')
    end

    it 'yields to block for missing key' do
      expect(h.fetch(:missing) { |k| "no #{k}" }).to eq('no missing')
    end

    it 'raises KeyError for missing key without default' do
      expect { h.fetch(:missing) }.to raise_error(KeyError)
    end
  end

  describe '.deep_convert' do
    it 'converts nested hashes to IndifferentHash' do
      input = { 'a' => { 'b' => { 'c' => 1 } } }
      result = described_class.deep_convert(input)
      expect(result).to be_a(described_class)
      expect(result[:a]).to be_a(described_class)
      expect(result[:a][:b]).to be_a(described_class)
      expect(result[:a][:b][:c]).to eq(1)
    end

    it 'converts arrays of hashes' do
      input = { 'items' => [{ 'name' => 'foo' }, { 'name' => 'bar' }] }
      result = described_class.deep_convert(input)
      expect(result[:items]).to be_an(Array)
      expect(result[:items][0]).to be_a(described_class)
      expect(result[:items][0][:name]).to eq('foo')
    end

    it 'preserves scalar values' do
      input = { 'str' => 'hello', 'num' => 42, 'bool' => true, 'nil_val' => nil }
      result = described_class.deep_convert(input)
      expect(result[:str]).to eq('hello')
      expect(result[:num]).to eq(42)
      expect(result[:bool]).to be true
      expect(result[:nil_val]).to be_nil
    end

    it 'handles non-hash non-array input' do
      expect(described_class.deep_convert('hello')).to eq('hello')
      expect(described_class.deep_convert(42)).to eq(42)
      expect(described_class.deep_convert(nil)).to be_nil
    end

    it 'stores keys as strings internally' do
      input = { foo: 'bar' }
      result = described_class.deep_convert(input)
      # Keys are converted to strings by deep_convert
      expect(result['foo']).to eq('bar')
      expect(result[:foo]).to eq('bar')
    end
  end
end
