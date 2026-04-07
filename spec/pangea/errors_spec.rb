# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Pangea::Errors do
  describe Pangea::Errors::PangeaError do
    it 'stores message' do
      error = described_class.new('something broke')
      expect(error.message).to eq('something broke')
    end

    it 'stores context' do
      error = described_class.new('fail', context: { resource: 'vpc', region: 'us-east-1' })
      expect(error.context[:resource]).to eq('vpc')
      expect(error.context[:region]).to eq('us-east-1')
    end

    it 'defaults context to empty hash' do
      error = described_class.new('fail')
      expect(error.context).to eq({})
    end

    it 'records timestamp' do
      error = described_class.new('fail')
      expect(error.timestamp).to be_a(Time)
      expect(error.timestamp).to be_within(2).of(Time.now)
    end

    describe '#detailed_message' do
      it 'includes timestamp, class, and message' do
        error = described_class.new('test error')
        msg = error.detailed_message
        expect(msg).to include('Pangea::Errors::PangeaError')
        expect(msg).to include('test error')
      end

      it 'includes context when present' do
        error = described_class.new('fail', context: { key: 'value' })
        msg = error.detailed_message
        expect(msg).to include('Context:')
        expect(msg).to include('key: value')
      end
    end

    describe '#to_h' do
      it 'returns structured hash' do
        error = described_class.new('fail', context: { a: 1 })
        h = error.to_h
        expect(h[:error_type]).to eq('Pangea::Errors::PangeaError')
        expect(h[:message]).to eq('fail')
        expect(h[:context]).to eq({ a: 1 })
        expect(h[:timestamp]).to be_a(String)
      end
    end

    describe 'cause chain' do
      it 'captures nested causes' do
        begin
          begin
            raise StandardError, 'root cause'
          rescue => e
            raise described_class.new('wrapper', cause: e)
          end
        rescue => error
          expect(error.cause_chain).not_to be_empty
          expect(error.cause_chain.first[:type]).to eq('StandardError')
          expect(error.cause_chain.first[:message]).to eq('root cause')
        end
      end

      it 'limits cause chain depth to 10' do
        chain = described_class.new('test').send(:build_cause_chain, nil)
        expect(chain).to eq([])
      end
    end
  end

  describe Pangea::Errors::ValidationError do
    describe '.invalid_attribute' do
      it 'creates error with attribute details' do
        error = described_class.invalid_attribute('aws_vpc', 'cidr', 'bad', '10.0.0.0/16')
        expect(error.message).to include('aws_vpc')
        expect(error.message).to include('cidr')
        expect(error.context[:resource]).to eq('aws_vpc')
        expect(error.context[:attribute]).to eq('cidr')
      end
    end

    describe '.missing_required' do
      it 'creates error for missing attribute' do
        error = described_class.missing_required('aws_vpc', 'cidr_block')
        expect(error.message).to include('Missing required')
        expect(error.message).to include('cidr_block')
      end
    end

    describe '.invalid_reference' do
      it 'creates error for invalid reference' do
        error = described_class.invalid_reference('vpc', 'subnet', 'not found')
        expect(error.message).to include('Invalid reference')
        expect(error.context[:source]).to eq('vpc')
        expect(error.context[:target]).to eq('subnet')
      end
    end

    describe '.invalid_type' do
      it 'creates error for type mismatch' do
        error = described_class.invalid_type('aws_vpc', 'cidr', 'String', 'Integer')
        expect(error.message).to include('Invalid type')
        expect(error.context[:expected_type]).to eq('String')
        expect(error.context[:actual_type]).to eq('Integer')
      end
    end

    describe '.out_of_range' do
      it 'creates error for out of range value' do
        error = described_class.out_of_range('aws_vpc', 'port', 70000, '0-65535')
        expect(error.message).to include('out of range')
        expect(error.context[:value]).to eq(70000)
      end
    end
  end

  describe Pangea::Errors::SynthesisError do
    describe '.invalid_template' do
      it 'creates error for invalid template' do
        error = described_class.invalid_template('my-template', 'syntax error')
        expect(error.message).to include('my-template')
        expect(error.message).to include('syntax error')
      end
    end

    describe '.circular_dependency' do
      it 'creates error for circular dependency' do
        error = described_class.circular_dependency('vpc', 'subnet')
        expect(error.message).to include('Circular dependency')
        expect(error.context[:resource1]).to eq('vpc')
        expect(error.context[:resource2]).to eq('subnet')
      end
    end
  end

  describe Pangea::Errors::ResourceNotFoundError do
    it 'creates error with type and name' do
      error = described_class.new('aws_vpc', 'main')
      expect(error.message).to include('aws_vpc.main')
      expect(error.context[:resource_type]).to eq('aws_vpc')
      expect(error.context[:resource_name]).to eq('main')
    end
  end
end
