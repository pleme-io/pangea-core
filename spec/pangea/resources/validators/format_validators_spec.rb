# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Pangea::Resources::Validators::FormatValidators do
  let(:instance) do
    mod = described_class
    klass = Class.new { include mod }
    klass.new
  end

  describe '#terraform_interpolation?' do
    it 'returns true for valid terraform interpolation' do
      expect(instance.terraform_interpolation?('${aws_vpc.main.id}')).to be true
    end

    it 'returns false for plain strings' do
      expect(instance.terraform_interpolation?('hello')).to be false
    end

    it 'returns false for partial interpolation' do
      expect(instance.terraform_interpolation?('prefix-${ref}')).to be false
    end

    it 'returns false for non-string values' do
      expect(instance.terraform_interpolation?(123)).to be false
      expect(instance.terraform_interpolation?(nil)).to be false
    end

    it 'returns false for empty interpolation' do
      expect(instance.terraform_interpolation?('${}')).to be false
    end
  end

  describe '#valid_hex!' do
    it 'accepts valid hex strings of specified length' do
      expect(instance.valid_hex!('abcdef12', length: 8)).to eq('abcdef12')
    end

    it 'accepts uppercase hex' do
      expect(instance.valid_hex!('ABCDEF12', length: 8)).to eq('ABCDEF12')
    end

    it 'rejects non-hex characters' do
      expect { instance.valid_hex!('xyz12345', length: 8) }.to raise_error(NameError)
    end

    it 'rejects wrong length' do
      expect { instance.valid_hex!('abcd', length: 8) }.to raise_error(NameError)
    end

    it 'allows terraform interpolation when allow_interpolation is true' do
      expect(instance.valid_hex!('${var.hex}', length: 8, allow_interpolation: true)).to eq('${var.hex}')
    end

    it 'rejects terraform interpolation when allow_interpolation is false' do
      expect { instance.valid_hex!('${var.hex}', length: 8, allow_interpolation: false) }.to raise_error(NameError)
    end

    it 'rejects empty string' do
      expect { instance.valid_hex!('', length: 8) }.to raise_error(NameError)
    end
  end

  describe '#valid_json!' do
    it 'accepts valid JSON' do
      json = '{"key": "value"}'
      expect(instance.valid_json!(json)).to eq(json)
    end

    it 'accepts JSON arrays' do
      json = '[1, 2, 3]'
      expect(instance.valid_json!(json)).to eq(json)
    end

    it 'rejects invalid JSON' do
      expect { instance.valid_json!('{invalid}') }.to raise_error(NameError)
    end

    it 'truncates long invalid JSON in error message' do
      long_invalid = 'x' * 100
      expect { instance.valid_json!(long_invalid) }.to raise_error(NameError)
    end
  end

  describe '#valid_base64!' do
    it 'accepts valid base64 strings' do
      encoded = Base64.strict_encode64('hello world')
      expect(instance.valid_base64!(encoded)).to eq(encoded)
    end

    it 'accepts base64 with padding' do
      encoded = Base64.strict_encode64('hi')
      expect(instance.valid_base64!(encoded)).to eq(encoded)
    end

    it 'rejects strings with invalid base64 characters' do
      expect { instance.valid_base64!('not valid base64!!!') }.to raise_error(NameError)
    end

    it 'accepts empty string as valid base64' do
      expect(instance.valid_base64!('')).to eq('')
    end
  end
end
