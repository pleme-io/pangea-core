# frozen_string_literal: true

require 'spec_helper'
require 'json'

RSpec.describe Pangea::Logging::StructuredLogger do
  let(:output) { StringIO.new }
  let(:logger) { described_class.new(output: output, level: :debug, format: :json) }

  describe 'initialization' do
    it 'defaults to info level' do
      l = described_class.new(output: output, format: :json)
      expect(l.log_level).to eq(1)
    end

    it 'accepts custom log level' do
      l = described_class.new(output: output, level: :error, format: :json)
      expect(l.log_level).to eq(3)
    end

    it 'generates a correlation ID' do
      expect(logger.correlation_id).to match(/\A[0-9a-f-]{36}\z/)
    end

    it 'accepts custom correlation ID' do
      l = described_class.new(output: output, correlation_id: 'custom-id')
      expect(l.correlation_id).to eq('custom-id')
    end
  end

  describe 'log level methods' do
    it 'logs debug messages at debug level' do
      logger.debug('test debug')
      output.rewind
      entry = JSON.parse(output.read.strip)
      expect(entry['level']).to eq('DEBUG')
      expect(entry['message']).to eq('test debug')
    end

    it 'logs info messages' do
      logger.info('test info')
      output.rewind
      entry = JSON.parse(output.read.strip)
      expect(entry['level']).to eq('INFO')
    end

    it 'logs warn messages' do
      logger.warn('test warn')
      output.rewind
      entry = JSON.parse(output.read.strip)
      expect(entry['level']).to eq('WARN')
    end

    it 'logs error messages' do
      logger.error('test error')
      output.rewind
      entry = JSON.parse(output.read.strip)
      expect(entry['level']).to eq('ERROR')
    end

    it 'logs fatal messages' do
      logger.fatal('test fatal')
      output.rewind
      entry = JSON.parse(output.read.strip)
      expect(entry['level']).to eq('FATAL')
    end

    it 'filters below log level' do
      l = described_class.new(output: output, level: :error, format: :json)
      l.info('should not appear')
      output.rewind
      expect(output.read).to be_empty
    end

    it 'includes context in log entries' do
      logger.info('with context', region: 'us-east-1', service: 'vpc')
      output.rewind
      entry = JSON.parse(output.read.strip)
      expect(entry['region']).to eq('us-east-1')
      expect(entry['service']).to eq('vpc')
    end
  end

  describe '#add_metadata / #clear_metadata' do
    it 'includes metadata in log entries' do
      logger.add_metadata(:env, 'production')
      logger.info('with metadata')
      output.rewind
      entry = JSON.parse(output.read.strip)
      expect(entry['env']).to eq('production')
    end

    it 'clears metadata' do
      logger.add_metadata(:env, 'production')
      logger.clear_metadata
      logger.info('without metadata')
      output.rewind
      entry = JSON.parse(output.read.strip)
      expect(entry).not_to have_key('env')
    end
  end

  describe '#child' do
    it 'creates child logger with inherited settings' do
      child = logger.child(component: 'vpc')
      expect(child.correlation_id).to eq(logger.correlation_id)
      expect(child.log_level).to eq(logger.log_level)
    end

    it 'merges parent metadata with child context' do
      logger.add_metadata(:env, 'staging')
      child = logger.child(component: 'vpc')
      child.info('child log')
      output.rewind
      entry = JSON.parse(output.read.strip)
      expect(entry['env']).to eq('staging')
      expect(entry['component']).to eq('vpc')
    end
  end

  describe '#measure' do
    it 'measures operation duration' do
      result = logger.measure('test-op') { 42 }
      expect(result).to eq(42)

      output.rewind
      lines = output.read.strip.split("\n")
      expect(lines.size).to eq(2)

      started = JSON.parse(lines[0])
      completed = JSON.parse(lines[1])
      expect(started['message']).to include('started')
      expect(completed['message']).to include('completed')
      expect(completed).to have_key('duration_ms')
    end

    it 'logs failure when block raises' do
      expect {
        logger.measure('failing-op') { raise 'boom' }
      }.to raise_error(RuntimeError, 'boom')

      output.rewind
      lines = output.read.strip.split("\n")
      failed_entry = JSON.parse(lines.last)
      expect(failed_entry['message']).to include('failed')
      expect(failed_entry['error']).to eq('RuntimeError')
    end
  end

  describe '#metric' do
    it 'records a metric' do
      logger.metric('requests.count', 42, unit: 'count', endpoint: '/api')
      output.rewind
      entry = JSON.parse(output.read.strip)
      expect(entry['metric_name']).to eq('requests.count')
      expect(entry['metric_value']).to eq(42)
      expect(entry['metric_unit']).to eq('count')
    end
  end

  describe 'output formats' do
    it 'outputs in pretty format' do
      l = described_class.new(output: output, level: :debug, format: :pretty)
      l.info('pretty message')
      output.rewind
      line = output.read.strip
      expect(line).to include('[INFO ]')
      expect(line).to include('pretty message')
    end

    it 'outputs in logfmt format' do
      l = described_class.new(output: output, level: :debug, format: :logfmt)
      l.info('logfmt message')
      output.rewind
      line = output.read.strip
      expect(line).to include('level=INFO')
      expect(line).to include('message=')
    end

    it 'outputs in simple format' do
      l = described_class.new(output: output, level: :debug, format: :simple)
      l.info('simple message')
      output.rewind
      line = output.read.strip
      expect(line).to eq('INFO - simple message')
    end
  end

  describe 'system context' do
    it 'includes pid and thread_id in entries' do
      logger.info('context test')
      output.rewind
      entry = JSON.parse(output.read.strip)
      expect(entry['pid']).to eq(Process.pid)
      expect(entry).to have_key('thread_id')
      expect(entry['ruby_version']).to eq(RUBY_VERSION)
    end
  end
end
