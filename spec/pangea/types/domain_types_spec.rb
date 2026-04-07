# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Pangea::Types domain types' do
  describe 'Identifier' do
    it 'accepts valid identifiers' do
      expect(Pangea::Types::Identifier['valid-name']).to eq('valid-name')
      expect(Pangea::Types::Identifier['a123']).to eq('a123')
      expect(Pangea::Types::Identifier['test_name']).to eq('test_name')
    end

    it 'rejects identifiers starting with numbers' do
      expect { Pangea::Types::Identifier['123abc'] }.to raise_error(Dry::Types::ConstraintError)
    end

    it 'rejects identifiers with uppercase' do
      expect { Pangea::Types::Identifier['Invalid'] }.to raise_error(Dry::Types::ConstraintError)
    end

    it 'rejects empty strings' do
      expect { Pangea::Types::Identifier[''] }.to raise_error(Dry::Types::ConstraintError)
    end

    it 'rejects strings longer than 63 chars' do
      expect { Pangea::Types::Identifier['a' * 64] }.to raise_error(Dry::Types::ConstraintError)
    end
  end

  describe 'StateBackendType' do
    it 'accepts :s3' do
      expect(Pangea::Types::StateBackendType[:s3]).to eq(:s3)
    end

    it 'accepts :local' do
      expect(Pangea::Types::StateBackendType[:local]).to eq(:local)
    end

    it 'rejects invalid backends' do
      expect { Pangea::Types::StateBackendType[:consul] }.to raise_error(Dry::Types::ConstraintError)
    end
  end

  describe 'TerraformVersion' do
    it 'accepts valid semver' do
      expect(Pangea::Types::TerraformVersion['1.5.0']).to eq('1.5.0')
    end

    it 'rejects non-semver strings' do
      expect { Pangea::Types::TerraformVersion['latest'] }.to raise_error(Dry::Types::ConstraintError)
    end
  end

  describe 'Version' do
    it 'accepts semver with prerelease' do
      expect(Pangea::Types::Version['1.0.0-beta']).to eq('1.0.0-beta')
    end

    it 'accepts plain semver' do
      expect(Pangea::Types::Version['0.0.1']).to eq('0.0.1')
    end
  end

  describe 'SymbolizedHash' do
    it 'symbolizes string keys' do
      result = Pangea::Types::SymbolizedHash[{ 'key' => 'value' }]
      expect(result).to eq({ key: 'value' })
    end

    it 'passes through already-symbolized hashes' do
      result = Pangea::Types::SymbolizedHash[{ key: 'value' }]
      expect(result).to eq({ key: 'value' })
    end

    it 'symbolizes nested hash keys' do
      result = Pangea::Types::SymbolizedHash[{ 'outer' => { 'inner' => 'val' } }]
      expect(result[:outer]).to eq({ inner: 'val' })
    end
  end

  describe 'StrippedString' do
    it 'strips whitespace' do
      expect(Pangea::Types::StrippedString['  hello  ']).to eq('hello')
    end
  end

  describe 'EnvironmentVariable' do
    it 'accepts valid env var names' do
      expect(Pangea::Types::EnvironmentVariable['AWS_REGION']).to eq('AWS_REGION')
    end

    it 'rejects lowercase' do
      expect { Pangea::Types::EnvironmentVariable['aws_region'] }.to raise_error(Dry::Types::ConstraintError)
    end
  end

  describe 'HttpUrl' do
    it 'accepts http URLs' do
      expect(Pangea::Types::HttpUrl['http://example.com']).to eq('http://example.com')
    end

    it 'accepts https URLs' do
      expect(Pangea::Types::HttpUrl['https://example.com/path']).to eq('https://example.com/path')
    end

    it 'rejects non-http URLs' do
      expect { Pangea::Types::HttpUrl['ftp://example.com'] }.to raise_error(Dry::Types::ConstraintError)
    end
  end

  describe 'TerraformAction' do
    it 'accepts valid actions' do
      %i[plan apply destroy init].each do |action|
        expect(Pangea::Types::TerraformAction[action]).to eq(action)
      end
    end

    it 'rejects invalid actions' do
      expect { Pangea::Types::TerraformAction[:refresh] }.to raise_error(Dry::Types::ConstraintError)
    end
  end

  describe 'ConfigFormat' do
    it 'accepts supported formats' do
      %i[yaml yml json toml rb].each do |fmt|
        expect(Pangea::Types::ConfigFormat[fmt]).to eq(fmt)
      end
    end
  end

  describe 'StringArray' do
    it 'accepts arrays of strings' do
      expect(Pangea::Types::StringArray[['a', 'b']]).to eq(['a', 'b'])
    end

    it 'rejects arrays with non-strings' do
      expect { Pangea::Types::StringArray[[1, 2]] }.to raise_error(Dry::Types::ConstraintError)
    end
  end

  describe 'FilePath' do
    it 'accepts non-empty strings' do
      expect(Pangea::Types::FilePath['/path/to/file']).to eq('/path/to/file')
    end

    it 'rejects empty strings' do
      expect { Pangea::Types::FilePath[''] }.to raise_error(Dry::Types::ConstraintError)
    end
  end
end
