# frozen_string_literal: true

require 'spec_helper'
require 'json'
require 'time'

RSpec.describe Pangea::Logging::Formatters do
  let(:formatter_class) do
    Class.new do
      include Pangea::Logging::Formatters
    end
  end

  let(:formatter) { formatter_class.new }

  let(:entry) do
    {
      timestamp: Time.now.iso8601(3),
      level: 'INFO',
      message: 'test message',
      correlation_id: 'abc-123',
      pid: 12345,
      thread_id: 67890,
      ruby_version: '3.3.0',
      custom_key: 'custom_value'
    }
  end

  describe '#format_pretty' do
    it 'includes timestamp, level, and message' do
      result = formatter.format_pretty(entry)
      expect(result).to include('[INFO ]')
      expect(result).to include('test message')
    end

    it 'includes context key-value pairs' do
      result = formatter.format_pretty(entry)
      expect(result).to include('custom_key=custom_value')
    end

    it 'excludes standard context keys from context string' do
      result = formatter.format_pretty(entry)
      expect(result).not_to include('pid=12345')
      expect(result).not_to include('thread_id=')
    end
  end

  describe '#format_json' do
    it 'produces valid JSON' do
      result = formatter.format_json(entry)
      parsed = JSON.parse(result)
      expect(parsed['message']).to eq('test message')
      expect(parsed['level']).to eq('INFO')
    end
  end

  describe '#format_logfmt' do
    it 'produces key=value pairs' do
      result = formatter.format_logfmt(entry)
      expect(result).to include('level=INFO')
      expect(result).to include('message=')
    end

    it 'quotes values with spaces' do
      entry_with_spaces = { message: 'hello world', level: 'INFO' }
      result = formatter.format_logfmt(entry_with_spaces)
      expect(result).to include('"hello world"')
    end
  end

  describe '#format_simple' do
    it 'outputs level and message' do
      result = formatter.format_simple(entry)
      expect(result).to eq('INFO - test message')
    end
  end

  describe 'format_value (private)' do
    it 'quotes strings with spaces' do
      result = formatter.send(:format_value, 'hello world')
      expect(result).to eq('"hello world"')
    end

    it 'returns plain strings without spaces' do
      result = formatter.send(:format_value, 'simple')
      expect(result).to eq('simple')
    end

    it 'summarizes hashes' do
      result = formatter.send(:format_value, { a: 1, b: 2 })
      expect(result).to eq('{2 items}')
    end

    it 'summarizes arrays' do
      result = formatter.send(:format_value, [1, 2, 3])
      expect(result).to eq('[3 items]')
    end

    it 'converts other types to string' do
      result = formatter.send(:format_value, 42)
      expect(result).to eq('42')
    end
  end

  describe 'constants' do
    it 'LEVEL_ROLES is frozen' do
      expect(described_class::LEVEL_ROLES).to be_frozen
    end

    it 'EXCLUDED_CONTEXT_KEYS is frozen' do
      expect(described_class::EXCLUDED_CONTEXT_KEYS).to be_frozen
    end
  end
end
