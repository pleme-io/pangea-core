# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Pangea::Validation::Result do
  let(:result) { described_class.new }

  describe '#valid?' do
    it 'returns true when no errors' do
      expect(result.valid?).to be true
    end

    it 'returns false when errors are present' do
      result.add_error('something broke')
      expect(result.valid?).to be false
    end
  end

  describe '#add_error' do
    it 'adds an error message' do
      result.add_error('error 1')
      expect(result.errors).to include('error 1')
    end
  end

  describe '#add_warning' do
    it 'adds a warning message' do
      result.add_warning('warning 1')
      expect(result.warnings).to include('warning 1')
    end
  end

  describe '#add_suggestion' do
    it 'adds a suggestion message' do
      result.add_suggestion('suggestion 1')
      expect(result.suggestions).to include('suggestion 1')
    end
  end

  describe '#finalize!' do
    it 'prevents further modifications' do
      result.add_error('error')
      result.finalize!
      expect { result.add_error('another') }.to raise_error(FrozenError)
      expect { result.add_warning('warn') }.to raise_error(FrozenError)
      expect { result.add_suggestion('suggest') }.to raise_error(FrozenError)
    end

    it 'returns self for chaining' do
      expect(result.finalize!).to eq(result)
    end

    it 'freezes internal arrays' do
      result.add_error('e')
      result.add_warning('w')
      result.add_suggestion('s')
      result.finalize!
      expect(result.errors).to be_frozen
      expect(result.warnings).to be_frozen
      expect(result.suggestions).to be_frozen
    end
  end

  describe '#finalized?' do
    it 'returns false before finalize!' do
      expect(result.finalized?).to be false
    end

    it 'returns true after finalize!' do
      result.finalize!
      expect(result.finalized?).to be true
    end
  end

  describe '#to_s' do
    it 'returns empty string for clean result' do
      expect(result.to_s).to eq('')
    end

    it 'formats errors' do
      result.add_error('bad thing')
      output = result.to_s
      expect(output).to include('Errors:')
      expect(output).to include('- bad thing')
    end

    it 'formats warnings' do
      result.add_warning('watch out')
      output = result.to_s
      expect(output).to include('Warnings:')
      expect(output).to include('- watch out')
    end

    it 'formats suggestions' do
      result.add_suggestion('try this')
      output = result.to_s
      expect(output).to include('Suggestions:')
      expect(output).to include('- try this')
    end

    it 'combines all categories' do
      result.add_error('err')
      result.add_warning('warn')
      result.add_suggestion('suggest')
      output = result.to_s
      expect(output).to include('Errors:')
      expect(output).to include('Warnings:')
      expect(output).to include('Suggestions:')
    end
  end

  describe 'frozen accessors return safe copies' do
    it 'errors array cannot mutate internal state' do
      result.add_error('err')
      errors = result.errors
      expect(errors).to be_frozen
    end
  end
end

RSpec.describe Pangea::Validation::Helpers do
  let(:klass) do
    Class.new do
      include Pangea::Validation::Helpers
    end
  end

  let(:instance) { klass.new }

  describe '#validate_name!' do
    it 'accepts valid symbol names' do
      expect { instance.validate_name!(:valid_name) }.not_to raise_error
    end

    it 'accepts valid string names' do
      expect { instance.validate_name!('valid_name') }.not_to raise_error
    end

    it 'rejects names starting with numbers' do
      expect { instance.validate_name!('1invalid') }.to raise_error(Pangea::Errors::ValidationError)
    end

    it 'rejects names with uppercase' do
      expect { instance.validate_name!('Invalid') }.to raise_error(Pangea::Errors::ValidationError)
    end

    it 'rejects non-string/symbol types' do
      expect { instance.validate_name!(123) }.to raise_error(Pangea::Errors::ValidationError)
    end
  end

  describe '#validate_required_attributes' do
    it 'returns valid result when all required attributes present' do
      result = instance.validate_required_attributes('aws_vpc', { cidr: '10.0.0.0/16', name: 'test' }, [:cidr, :name])
      expect(result.valid?).to be true
    end

    it 'returns errors for missing attributes' do
      result = instance.validate_required_attributes('aws_vpc', {}, [:cidr, :name])
      expect(result.valid?).to be false
      expect(result.errors.size).to eq(2)
    end

    it 'adds suggestions for common missing attributes' do
      result = instance.validate_required_attributes('aws_instance', {}, [:subnet_id])
      expect(result.suggestions).not_to be_empty
    end

    it 'adds suggestion for vpc_id' do
      result = instance.validate_required_attributes('aws_subnet', {}, [:vpc_id])
      expect(result.suggestions.any? { |s| s.include?('vpc') }).to be true
    end

    it 'adds suggestion for security_group_ids' do
      result = instance.validate_required_attributes('aws_instance', {}, [:security_group_ids])
      expect(result.suggestions.any? { |s| s.include?('security_group') }).to be true
    end
  end
end
