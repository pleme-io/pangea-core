# frozen_string_literal: true

require 'spec_helper'
require 'pangea/testing'
require 'terraform-synthesizer'

RSpec.describe Pangea::Resources::ResourceBuilder do
  include Pangea::Testing::SynthesisTestHelpers

  # Test attribute classes
  before(:all) do
    # Simple attributes for testing
    unless defined?(TestSimpleAttributes)
      TestSimpleAttributes = Class.new(Pangea::Resources::BaseAttributes) do
        attribute :name, Dry::Types['strict.string']
        attribute :description, Dry::Types['strict.string'].optional.default(nil)
        attribute :enabled, Dry::Types['strict.bool'].optional.default(nil)
        attribute :labels, Dry::Types['nominal.hash'].default({}.freeze)
        attribute :count, Dry::Types['coercible.integer'].optional.default(nil)
      end
    end

    # Module using ResourceBuilder for a simple resource
    unless defined?(TestSimpleResource)
      TestSimpleResource = Module.new do
        include Pangea::Resources::ResourceBuilder

        define_resource :test_simple,
          attributes_class: TestSimpleAttributes,
          outputs: { id: :id, self_link: :self_link },
          map: [:name],
          map_present: [:description, :count],
          map_bool: [:enabled],
          labels: :labels
      end
    end

    # Module using ResourceBuilder with tags instead of labels
    unless defined?(TestTaggedResource)
      TestTaggedResource = Module.new do
        include Pangea::Resources::ResourceBuilder

        define_resource :test_tagged,
          attributes_class: TestSimpleAttributes,
          outputs: { id: :id },
          map: [:name],
          tags: :labels  # reuse labels attr as tags for testing
      end
    end

    # Module using ResourceBuilder with custom block
    unless defined?(TestCustomBlockResource)
      TestCustomBlockResource = Module.new do
        include Pangea::Resources::ResourceBuilder

        define_resource :test_custom,
          attributes_class: TestSimpleAttributes,
          outputs: { id: :id },
          map: [:name],
          map_present: [:description] do |r, attrs|
            if attrs.count
              r.nested_block attrs.count
            end
          end
      end
    end
  end

  let(:synth) { create_synthesizer }

  describe '.define_resource' do
    it 'defines a method with the resource type name' do
      synth.extend(TestSimpleResource)
      expect(synth).to respond_to(:test_simple)
    end

    it 'registers resource definition metadata' do
      defs = TestSimpleResource.resource_definitions
      expect(defs).to have_key(:test_simple)
      expect(defs[:test_simple][:map]).to eq([:name])
      expect(defs[:test_simple][:map_present]).to eq([:description, :count])
      expect(defs[:test_simple][:map_bool]).to eq([:enabled])
    end
  end

  describe 'generated resource method' do
    it 'creates terraform resource with required attributes' do
      synth.extend(TestSimpleResource)
      synth.test_simple(:test, { name: 'my-resource' })
      result = normalize_synthesis(synth.synthesis)

      config = result.dig('resource', 'test_simple', 'test')
      expect(config).not_to be_nil
      expect(config['name']).to eq('my-resource')
    end

    it 'includes map_present attributes when non-nil' do
      synth.extend(TestSimpleResource)
      synth.test_simple(:test, { name: 'my-resource', description: 'A test', count: 5 })
      result = normalize_synthesis(synth.synthesis)

      config = result.dig('resource', 'test_simple', 'test')
      expect(config['description']).to eq('A test')
      expect(config['count']).to eq(5)
    end

    it 'omits map_present attributes when nil' do
      synth.extend(TestSimpleResource)
      synth.test_simple(:test, { name: 'my-resource' })
      result = normalize_synthesis(synth.synthesis)

      config = result.dig('resource', 'test_simple', 'test')
      expect(config).not_to have_key('description')
      expect(config).not_to have_key('count')
    end

    it 'includes boolean attributes when non-nil' do
      synth.extend(TestSimpleResource)
      synth.test_simple(:test, { name: 'my-resource', enabled: false })
      result = normalize_synthesis(synth.synthesis)

      config = result.dig('resource', 'test_simple', 'test')
      expect(config['enabled']).to eq(false)
    end

    it 'omits boolean attributes when nil' do
      synth.extend(TestSimpleResource)
      synth.test_simple(:test, { name: 'my-resource' })
      result = normalize_synthesis(synth.synthesis)

      config = result.dig('resource', 'test_simple', 'test')
      expect(config).not_to have_key('enabled')
    end

    it 'includes labels when non-empty' do
      synth.extend(TestSimpleResource)
      synth.test_simple(:test, { name: 'my-resource', labels: { 'env' => 'prod' } })
      result = normalize_synthesis(synth.synthesis)

      config = result.dig('resource', 'test_simple', 'test')
      expect(config['labels']).to eq({ 'env' => 'prod' })
    end

    it 'omits labels when empty' do
      synth.extend(TestSimpleResource)
      synth.test_simple(:test, { name: 'my-resource' })
      result = normalize_synthesis(synth.synthesis)

      config = result.dig('resource', 'test_simple', 'test')
      expect(config).not_to have_key('labels')
    end

    it 'handles tags parameter' do
      synth.extend(TestTaggedResource)
      synth.test_tagged(:test, { name: 'my-resource', labels: { 'env' => 'prod' } })
      result = normalize_synthesis(synth.synthesis)

      config = result.dig('resource', 'test_tagged', 'test')
      expect(config['labels']).to eq({ 'env' => 'prod' })
    end

    it 'returns ResourceReference with correct outputs' do
      synth.extend(TestSimpleResource)
      ref = synth.test_simple(:test, { name: 'my-resource' })

      expect(ref).to be_a(Pangea::Resources::ResourceReference)
      expect(ref.type).to eq('test_simple')
      expect(ref.outputs[:id]).to eq('${test_simple.test.id}')
      expect(ref.outputs[:self_link]).to eq('${test_simple.test.self_link}')
    end

    it 'stores resource_attributes on the reference' do
      synth.extend(TestSimpleResource)
      ref = synth.test_simple(:test, { name: 'my-resource', description: 'desc' })

      expect(ref.resource_attributes[:name]).to eq('my-resource')
      expect(ref.resource_attributes[:description]).to eq('desc')
    end

    it 'validates attributes via Dry::Struct' do
      synth.extend(TestSimpleResource)
      expect { synth.test_simple(:test, { __invalid__: true }) }
        .to raise_error(Dry::Struct::Error)
    end
  end

  describe 'custom block' do
    it 'executes custom block with resource DSL and attrs' do
      synth.extend(TestCustomBlockResource)
      synth.test_custom(:test, { name: 'my-resource', count: 42 })
      result = normalize_synthesis(synth.synthesis)

      config = result.dig('resource', 'test_custom', 'test')
      expect(config['name']).to eq('my-resource')
      expect(config['nested_block']).to eq(42)
    end

    it 'skips custom block logic when condition not met' do
      synth.extend(TestCustomBlockResource)
      synth.test_custom(:test, { name: 'my-resource' })
      result = normalize_synthesis(synth.synthesis)

      config = result.dig('resource', 'test_custom', 'test')
      expect(config).not_to have_key('nested_block')
    end
  end

  describe '.resource_definitions' do
    it 'returns empty hash for modules without definitions' do
      mod = Module.new { include Pangea::Resources::ResourceBuilder }
      expect(mod.resource_definitions).to eq({})
    end

    it 'returns metadata for defined resources' do
      defs = TestSimpleResource.resource_definitions
      expect(defs[:test_simple][:attributes_class]).to eq(TestSimpleAttributes)
      expect(defs[:test_simple][:outputs]).to eq({ id: :id, self_link: :self_link })
    end
  end
end
