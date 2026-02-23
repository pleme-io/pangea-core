# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Pangea::Resources::Base do
  let(:test_class) do
    Class.new do
      include Pangea::Resources::Base
      public :create_resource, :apply_attributes_to_resource, :resource_ref
    end
  end

  let(:instance) { test_class.new }

  let(:test_attributes_class) do
    Class.new(Pangea::Resources::BaseAttributes) do
      attribute :cidr_block, Pangea::Resources::Types::String
      attribute :name, Pangea::Resources::Types::String.default('default')
    end
  end

  describe Pangea::Resources::Base::ResourceDefinition do
    let(:definition) do
      described_class.new('aws_vpc', 'main', { cidr_block: '10.0.0.0/16' })
    end

    describe '#type' do
      it 'returns the resource type' do
        expect(definition.type).to eq('aws_vpc')
      end
    end

    describe '#name' do
      it 'returns the resource name' do
        expect(definition.name).to eq('main')
      end
    end

    describe '#attributes' do
      it 'returns the resource attributes' do
        expect(definition.attributes).to eq({ cidr_block: '10.0.0.0/16' })
      end
    end
  end

  describe '#create_resource' do
    it 'creates a resource definition with validated attributes' do
      result = instance.create_resource(
        'aws_vpc',
        'main',
        test_attributes_class,
        { cidr_block: '10.0.0.0/16' }
      )

      expect(result).to be_a(Pangea::Resources::Base::ResourceDefinition)
      expect(result.type).to eq('aws_vpc')
      expect(result.name).to eq('main')
      expect(result.attributes.cidr_block).to eq('10.0.0.0/16')
    end

    it 'raises when required attributes are missing' do
      expect do
        instance.create_resource('aws_vpc', 'main', test_attributes_class, {})
      end.to raise_error(Dry::Struct::Error)
    end
  end

  describe '#resource_ref' do
    it 'generates terraform reference strings' do
      expect(instance.resource_ref('aws_vpc', 'main', 'id')).to eq('${aws_vpc.main.id}')
      expect(instance.resource_ref('aws_subnet', 'public', 'cidr_block')).to eq('${aws_subnet.public.cidr_block}')
    end
  end

  describe '#apply_attributes_to_resource' do
    let(:recorder) do
      Class.new do
        attr_reader :calls

        def initialize
          @calls = []
        end

        def method_missing(method_name, *args, &block)
          if block
            @calls << { method: method_name, type: :block }
            block.call
          else
            @calls << { method: method_name, args: args }
          end
        end

        def respond_to_missing?(_method_name, _include_private = false)
          true
        end
      end.new
    end

    it 'applies simple key-value attributes' do
      instance.apply_attributes_to_resource(recorder, { cidr_block: '10.0.0.0/16', enable_dns: true })
      expect(recorder.calls).to include(
        { method: :cidr_block, args: ['10.0.0.0/16'] },
        { method: :enable_dns, args: [true] }
      )
    end

    it 'applies array attributes with non-hash items' do
      instance.apply_attributes_to_resource(recorder, { ingress: ['rule1', 'rule2'] })
      expect(recorder.calls).to include(
        { method: :ingress, args: ['rule1'] },
        { method: :ingress, args: ['rule2'] }
      )
    end
  end
end
