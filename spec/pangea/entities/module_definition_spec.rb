# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Pangea::Entities::ModuleDefinition do
  let(:basic_module) do
    described_class.new(name: 'test-module')
  end

  let(:full_module) do
    described_class.new(
      name: 'vpc-module',
      version: '1.2.3',
      description: 'A VPC module',
      author: 'Test Author',
      type: :composite,
      source: '/path/to/source.rb',
      inputs: {
        cidr: { required: true, description: 'VPC CIDR block', type: 'string' },
        name: { required: true, description: 'VPC name' },
        enable_dns: { required: false, description: 'Enable DNS', default: true }
      },
      outputs: {
        vpc_id: { description: 'The VPC ID' },
        subnet_ids: { description: 'Subnet IDs' }
      },
      dependencies: ['base-module']
    )
  end

  describe 'initialization' do
    it 'creates with minimal attributes' do
      expect(basic_module.name).to eq('test-module')
      expect(basic_module.version).to eq('0.0.1')
      expect(basic_module.type).to eq(:resource)
    end

    it 'creates with full attributes' do
      expect(full_module.name).to eq('vpc-module')
      expect(full_module.version).to eq('1.2.3')
      expect(full_module.type).to eq(:composite)
    end

    it 'defaults description to nil' do
      expect(basic_module.description).to be_nil
    end

    it 'defaults inputs and outputs to empty hashes' do
      expect(basic_module.inputs).to eq({})
      expect(basic_module.outputs).to eq({})
    end

    it 'defaults dependencies to empty array' do
      expect(basic_module.dependencies).to eq([])
    end
  end

  describe '#resource_module?' do
    it 'returns true for :resource type' do
      expect(basic_module.resource_module?).to be true
    end

    it 'returns true for :composite type' do
      expect(full_module.resource_module?).to be true
    end

    it 'returns false for :function type' do
      mod = described_class.new(name: 'fn-mod', type: :function)
      expect(mod.resource_module?).to be false
    end
  end

  describe '#function_module?' do
    it 'returns true for :function type' do
      mod = described_class.new(name: 'fn-mod', type: :function)
      expect(mod.function_module?).to be true
    end

    it 'returns true for :composite type' do
      expect(full_module.function_module?).to be true
    end

    it 'returns false for :resource type' do
      expect(basic_module.function_module?).to be false
    end
  end

  describe '#load_path' do
    it 'returns path when path is set' do
      mod = described_class.new(name: 'test-mod', path: '/custom/path')
      expect(mod.load_path).to eq('/custom/path')
    end

    it 'returns dirname of source when only source is set' do
      expect(full_module.load_path).to eq('/path/to')
    end

    it 'returns default modules path when neither path nor source is set' do
      expect(basic_module.load_path).to eq('modules/test-module')
    end
  end

  describe '#required_inputs' do
    it 'returns keys of required inputs' do
      expect(full_module.required_inputs).to contain_exactly(:cidr, :name)
    end

    it 'returns empty for module with no inputs' do
      expect(basic_module.required_inputs).to eq([])
    end
  end

  describe '#optional_inputs' do
    it 'returns keys of optional inputs' do
      expect(full_module.optional_inputs).to contain_exactly(:enable_dns)
    end
  end

  describe '#validate_inputs' do
    it 'passes with all required inputs' do
      expect(full_module.validate_inputs(cidr: '10.0.0.0/16', name: 'test')).to be true
    end

    it 'raises for missing required inputs' do
      expect { full_module.validate_inputs(name: 'test') }.to raise_error(
        Pangea::Entities::ValidationError, /Missing required input: cidr/
      )
    end

    it 'raises for unknown inputs' do
      expect { full_module.validate_inputs(cidr: '10.0.0.0/16', name: 'test', bogus: 'val') }.to raise_error(
        Pangea::Entities::ValidationError, /Unknown input: bogus/
      )
    end

    it 'raises with multiple errors combined' do
      expect { full_module.validate_inputs(bogus: 'val') }.to raise_error(
        Pangea::Entities::ValidationError
      )
    end
  end

  describe '#to_documentation' do
    it 'includes module name' do
      expect(full_module.to_documentation).to include('# Module: vpc-module')
    end

    it 'includes version' do
      expect(full_module.to_documentation).to include('Version: 1.2.3')
    end

    it 'includes description' do
      expect(full_module.to_documentation).to include('A VPC module')
    end

    it 'includes author' do
      expect(full_module.to_documentation).to include('Author: Test Author')
    end

    it 'lists inputs with required markers' do
      doc = full_module.to_documentation
      expect(doc).to include('## Inputs')
      expect(doc).to include('(required)')
    end

    it 'lists outputs' do
      doc = full_module.to_documentation
      expect(doc).to include('## Outputs')
      expect(doc).to include('vpc_id')
    end

    it 'generates minimal docs for basic module' do
      doc = basic_module.to_documentation
      expect(doc).to include('# Module: test-module')
      expect(doc).not_to include('## Inputs')
      expect(doc).not_to include('## Outputs')
    end
  end

  describe 'Type constants' do
    it 'defines RESOURCE' do
      expect(Pangea::Entities::ModuleDefinition::Type::RESOURCE).to eq(:resource)
    end

    it 'defines FUNCTION' do
      expect(Pangea::Entities::ModuleDefinition::Type::FUNCTION).to eq(:function)
    end

    it 'defines COMPOSITE' do
      expect(Pangea::Entities::ModuleDefinition::Type::COMPOSITE).to eq(:composite)
    end
  end
end
