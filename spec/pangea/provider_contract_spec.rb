# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Pangea::ProviderContract do
  let(:valid_module) do
    Module.new do
      def aws_vpc(name, attrs = {})
        # resource method
      end

      def aws_subnet(name, attrs = {})
        # resource method
      end
    end
  end

  describe '.validate!' do
    it 'accepts a valid Module' do
      expect { described_class.validate!(valid_module) }.not_to raise_error
    end

    it 'rejects a Class' do
      klass = Class.new
      expect { described_class.validate!(klass) }.to raise_error(
        Pangea::ProviderContract::ViolationError, /must be a Module/
      )
    end

    it 'rejects non-module objects' do
      expect { described_class.validate!('not a module') }.to raise_error(
        Pangea::ProviderContract::ViolationError, /must be a Module/
      )
    end

    it 'validates prefix when provided' do
      expect { described_class.validate!(valid_module, prefix: 'aws_') }.not_to raise_error
    end

    it 'raises when no methods match prefix' do
      empty_mod = Module.new
      expect { described_class.validate!(empty_mod, prefix: 'aws_') }.to raise_error(
        Pangea::ProviderContract::ViolationError, /no methods starting with/
      )
    end
  end

  describe '.check' do
    it 'returns [true, []] for valid module' do
      valid, errors = described_class.check(valid_module)
      expect(valid).to be true
      expect(errors).to be_empty
    end

    it 'returns [false, errors] for invalid module' do
      valid, errors = described_class.check(Class.new)
      expect(valid).to be false
      expect(errors).not_to be_empty
    end

    it 'returns [false, errors] for prefix mismatch' do
      valid, errors = described_class.check(Module.new, prefix: 'gcp_')
      expect(valid).to be false
      expect(errors.first).to include('no methods starting with')
    end
  end

  describe 'Metadata' do
    let(:provider_module) do
      Module.new do
        extend Pangea::ProviderContract::Metadata

        def self.provider_prefix
          'test_'
        end

        def test_resource_a; end
        def test_resource_b; end
        def helper_method; end
      end
    end

    describe '#resource_count' do
      it 'counts methods matching the prefix' do
        expect(provider_module.resource_count).to eq(2)
      end
    end

    describe '#resource_names' do
      it 'lists resource method names sorted' do
        expect(provider_module.resource_names).to eq([:test_resource_a, :test_resource_b])
      end
    end

    describe '#provider_prefix' do
      it 'raises NotImplementedError without override' do
        mod = Module.new { extend Pangea::ProviderContract::Metadata }
        expect { mod.provider_prefix }.to raise_error(NotImplementedError)
      end
    end
  end
end
