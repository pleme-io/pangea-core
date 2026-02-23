# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Pangea::Resources::ResourceReference do
  let(:ref) do
    described_class.new(
      type: 'aws_vpc',
      name: :main,
      resource_attributes: { cidr_block: '10.0.0.0/16', enable_dns: true },
      outputs: { vpc_id: '${aws_vpc.main.id}', cidr: '10.0.0.0/16' }
    )
  end

  describe 'initialization' do
    it 'creates with required attributes' do
      r = described_class.new(
        type: 'aws_vpc',
        name: :main,
        resource_attributes: { cidr: '10.0.0.0/16' }
      )
      expect(r.type).to eq('aws_vpc')
      expect(r.name).to eq(:main)
      expect(r.resource_attributes).to eq({ cidr: '10.0.0.0/16' })
    end

    it 'coerces Symbol type to String' do
      r = described_class.new(
        type: :aws_vpc,
        name: :main,
        resource_attributes: {}
      )
      expect(r.type).to eq('aws_vpc')
    end

    it 'accepts string name' do
      r = described_class.new(
        type: 'aws_vpc',
        name: 'main',
        resource_attributes: {}
      )
      expect(r.name).to eq('main')
    end

    it 'defaults outputs to empty hash' do
      r = described_class.new(
        type: 'aws_vpc',
        name: :main,
        resource_attributes: {}
      )
      expect(r.outputs).to eq({})
    end

    it 'accepts attributes: as alias for resource_attributes:' do
      r = described_class.new(
        type: 'aws_vpc',
        name: :main,
        attributes: { cidr: '10.0.0.0/16' }
      )
      expect(r.resource_attributes).to eq({ cidr: '10.0.0.0/16' })
    end

    it 'accepts Dry::Struct as resource_attributes and coerces to Hash' do
      struct_class = Class.new(Dry::Struct) do
        attribute :foo, Pangea::Resources::Types::String
      end
      instance = struct_class.new(foo: 'bar')
      r = described_class.new(
        type: 'test',
        name: :test,
        resource_attributes: instance
      )
      expect(r.resource_attributes).to eq({ foo: 'bar' })
    end

    it 'accepts computed_properties' do
      r = described_class.new(
        type: 'aws_vpc',
        name: :main,
        resource_attributes: {},
        computed_properties: { subnet_count: 3 }
      )
      expect(r.computed_properties).to eq({ subnet_count: 3 })
    end

    it 'accepts computed as alias' do
      r = described_class.new(
        type: 'aws_vpc',
        name: :main,
        resource_attributes: {},
        computed: { zone: 'us-east-1a' }
      )
      expect(r.computed).to eq({ zone: 'us-east-1a' })
    end
  end

  describe '#resource_type' do
    it 'returns the type as a symbol' do
      expect(ref.resource_type).to eq(:aws_vpc)
    end
  end

  describe '#ref' do
    it 'generates terraform reference string' do
      expect(ref.ref(:id)).to eq('${aws_vpc.main.id}')
      expect(ref.ref(:cidr_block)).to eq('${aws_vpc.main.cidr_block}')
    end
  end

  describe '#[]' do
    it 'is an alias for ref' do
      expect(ref[:id]).to eq('${aws_vpc.main.id}')
      expect(ref[:arn]).to eq('${aws_vpc.main.arn}')
    end
  end

  describe '#id' do
    it 'returns terraform id reference' do
      expect(ref.id).to eq('${aws_vpc.main.id}')
    end
  end

  describe '#arn' do
    it 'returns terraform arn reference' do
      expect(ref.arn).to eq('${aws_vpc.main.arn}')
    end
  end

  describe '#method_missing' do
    it 'delegates to outputs when key exists' do
      expect(ref.vpc_id).to eq('${aws_vpc.main.id}')
      expect(ref.cidr).to eq('10.0.0.0/16')
    end

    it 'delegates to computed_properties when key exists' do
      r = described_class.new(
        type: 'aws_vpc',
        name: :main,
        resource_attributes: {},
        computed_properties: { subnet_count: 3 }
      )
      expect(r.subnet_count).to eq(3)
    end

    it 'delegates to computed when key exists' do
      r = described_class.new(
        type: 'aws_vpc',
        name: :main,
        resource_attributes: {},
        computed: { zone: 'us-east-1a' }
      )
      expect(r.zone).to eq('us-east-1a')
    end

    it 'delegates to computed_attributes for common attributes' do
      expect(ref.terraform_resource_name).to eq('aws_vpc.main')
    end

    it 'raises NoMethodError for unknown methods' do
      expect { ref.completely_unknown_method_xyz }.to raise_error(NoMethodError)
    end
  end

  describe '#respond_to_missing?' do
    it 'returns true for output keys' do
      expect(ref.respond_to?(:vpc_id)).to be true
      expect(ref.respond_to?(:cidr)).to be true
    end

    it 'returns true for computed_properties keys' do
      r = described_class.new(
        type: 'aws_vpc',
        name: :main,
        resource_attributes: {},
        computed_properties: { foo: 'bar' }
      )
      expect(r.respond_to?(:foo)).to be true
    end

    it 'returns true for computed_attributes methods' do
      expect(ref.respond_to?(:terraform_resource_name)).to be true
    end

    it 'returns false for unknown methods' do
      expect(ref.respond_to?(:completely_unknown_method_xyz)).to be false
    end
  end

  describe '#to_h' do
    it 'returns a hash with type, name, attributes, and outputs' do
      result = ref.to_h
      expect(result[:type]).to eq('aws_vpc')
      expect(result[:name]).to eq(:main)
      expect(result[:attributes]).to eq({ cidr_block: '10.0.0.0/16', enable_dns: true })
      expect(result[:outputs]).to eq({ vpc_id: '${aws_vpc.main.id}', cidr: '10.0.0.0/16' })
    end
  end

  describe '.register_computed_attributes' do
    after do
      # Clean up registry
      Pangea::Resources::ResourceReference.class_variable_set(:@@computed_attributes_registry, {})
    end

    it 'registers computed attributes classes for resource types' do
      custom_class = Class.new(Pangea::Resources::BaseComputedAttributes) do
        def custom_attr
          'custom_value'
        end
      end

      described_class.register_computed_attributes('aws_custom' => custom_class)
      r = described_class.new(
        type: 'aws_custom',
        name: :test,
        resource_attributes: {}
      )
      expect(r.computed_attributes).to be_a(custom_class)
      expect(r.custom_attr).to eq('custom_value')
    end
  end

  describe '#computed_attributes' do
    it 'returns BaseComputedAttributes when no custom class is registered' do
      expect(ref.computed_attributes).to be_a(Pangea::Resources::BaseComputedAttributes)
    end
  end
end
