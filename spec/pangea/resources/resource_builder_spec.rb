# frozen_string_literal: true

require 'spec_helper'
require 'pangea/testing'
require 'terraform-synthesizer'

RSpec.describe Pangea::Resources::ResourceBuilder do
  include Pangea::Testing::SynthesisTestHelpers

  # Test attribute classes
  before(:all) do
    # Simple attributes for testing
    # NOTE: Avoid using :count as an attribute name — it collides with
    # the Terraform meta-argument :count and gets stripped during
    # meta-argument separation.
    unless defined?(TestSimpleAttributes)
      TestSimpleAttributes = Class.new(Pangea::Resources::BaseAttributes) do
        attribute :name, Dry::Types['strict.string']
        attribute :description, Dry::Types['strict.string'].optional.default(nil)
        attribute :enabled, Dry::Types['strict.bool'].optional.default(nil)
        attribute :labels, Dry::Types['nominal.hash'].default({}.freeze)
        attribute :priority, Dry::Types['coercible.integer'].optional.default(nil)
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
          map_present: [:description, :priority],
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
            if attrs.priority
              r.nested_block attrs.priority
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
      expect(defs[:test_simple][:map_present]).to eq([:description, :priority])
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
      synth.test_simple(:test, { name: 'my-resource', description: 'A test', priority: 5 })
      result = normalize_synthesis(synth.synthesis)

      config = result.dig('resource', 'test_simple', 'test')
      expect(config['description']).to eq('A test')
      expect(config['priority']).to eq(5)
    end

    it 'omits map_present attributes when nil' do
      synth.extend(TestSimpleResource)
      synth.test_simple(:test, { name: 'my-resource' })
      result = normalize_synthesis(synth.synthesis)

      config = result.dig('resource', 'test_simple', 'test')
      expect(config).not_to have_key('description')
      expect(config).not_to have_key('priority')
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

    it 'raises ArgumentError for unknown attribute keys' do
      synth.extend(TestSimpleResource)
      expect { synth.test_simple(:test, { unknown_key: 'value', name: 'test' }) }
        .to raise_error(ArgumentError, /unknown attributes.*unknown_key/)
    end

    it 'includes valid attribute names in error message' do
      synth.extend(TestSimpleResource)
      expect { synth.test_simple(:test, { typo_field: 'x', name: 'test' }) }
        .to raise_error(ArgumentError, /Valid attributes:/)
    end

    it 'accepts valid attribute keys without error' do
      synth.extend(TestSimpleResource)
      expect {
        synth.test_simple(:test, { name: 'valid-resource', description: 'ok', enabled: true })
      }.not_to raise_error
    end

    it 'detects multiple unknown keys' do
      synth.extend(TestSimpleResource)
      expect { synth.test_simple(:test, { bad1: 'x', bad2: 'y', name: 'test' }) }
        .to raise_error(ArgumentError, /bad1.*bad2|bad2.*bad1/)
    end

    it 'raises ArgumentError (not Dry::Struct::Error) for unknown keys' do
      synth.extend(TestSimpleResource)
      expect { synth.test_simple(:test, { __invalid__: true }) }
        .to raise_error(ArgumentError)
    end

    it 'raises Dry::Struct::Error for missing required attributes (after unknown-key check passes)' do
      synth.extend(TestSimpleResource)
      # Empty hash has no unknown keys but is missing required :name
      expect { synth.test_simple(:test, {}) }
        .to raise_error(Dry::Struct::Error)
    end
  end

  describe 'Terraform meta-argument separation' do
    it 'passes lifecycle through without raising unknown key error' do
      synth.extend(TestSimpleResource)
      expect {
        synth.test_simple(:test, { name: 'meta-test', lifecycle: { prevent_destroy: true } })
      }.not_to raise_error
    end

    it 'renders lifecycle block in synthesis output' do
      synth.extend(TestSimpleResource)
      synth.test_simple(:test, { name: 'meta-test', lifecycle: { prevent_destroy: true } })
      result = normalize_synthesis(synth.synthesis)

      config = result.dig('resource', 'test_simple', 'test')
      expect(config['lifecycle']).to be_a(Hash)
      expect(config['lifecycle']['prevent_destroy']).to eq(true)
    end

    it 'passes depends_on through without raising' do
      synth.extend(TestSimpleResource)
      expect {
        synth.test_simple(:test, { name: 'meta-test', depends_on: ['other.resource'] })
      }.not_to raise_error
    end

    it 'renders depends_on in synthesis output' do
      synth.extend(TestSimpleResource)
      synth.test_simple(:test, { name: 'meta-test', depends_on: ['other.resource'] })
      result = normalize_synthesis(synth.synthesis)

      config = result.dig('resource', 'test_simple', 'test')
      expect(config['depends_on']).to eq(['other.resource'])
    end

    it 'passes count through without raising unknown key error' do
      synth.extend(TestSimpleResource)
      # :count is a Terraform meta-argument, not a resource attribute on TestSimpleAttributes.
      # It should be separated before unknown-key detection and not raise.
      expect {
        synth.test_simple(:test, { name: 'meta-test', count: 3 })
      }.not_to raise_error
    end

    it 'renders count in synthesis output as Terraform meta-argument' do
      synth.extend(TestSimpleResource)
      synth.test_simple(:test, { name: 'meta-test', count: 3 })
      result = normalize_synthesis(synth.synthesis)

      config = result.dig('resource', 'test_simple', 'test')
      expect(config['count']).to eq(3)
    end

    it 'passes for_each through without raising' do
      synth.extend(TestSimpleResource)
      expect {
        synth.test_simple(:test, { name: 'meta-test', for_each: { a: 1 } })
      }.not_to raise_error
    end

    it 'passes provider through without raising' do
      synth.extend(TestSimpleResource)
      expect {
        synth.test_simple(:test, { name: 'meta-test', provider: 'aws.west' })
      }.not_to raise_error
    end

    it 'passes provisioner through without raising' do
      synth.extend(TestSimpleResource)
      expect {
        synth.test_simple(:test, { name: 'meta-test', provisioner: { local_exec: { command: 'echo hi' } } })
      }.not_to raise_error
    end

    it 'still rejects unknown keys alongside meta-arguments' do
      synth.extend(TestSimpleResource)
      expect {
        synth.test_simple(:test, { name: 'meta-test', lifecycle: {}, bad_key: 'x' })
      }.to raise_error(ArgumentError, /bad_key/)
    end

    it 'does not include meta-arguments in the error message for unknown keys' do
      synth.extend(TestSimpleResource)
      expect {
        synth.test_simple(:test, { name: 'meta-test', lifecycle: {}, bad_key: 'x' })
      }.to raise_error(ArgumentError) { |e|
        expect(e.message).not_to include('lifecycle')
        expect(e.message).to include('bad_key')
      }
    end

    it 'combines multiple meta-arguments in a single resource' do
      synth.extend(TestSimpleResource)
      synth.test_simple(:test, {
        name: 'combined-meta',
        lifecycle: { prevent_destroy: true },
        depends_on: ['other.resource'],
      })
      result = normalize_synthesis(synth.synthesis)

      config = result.dig('resource', 'test_simple', 'test')
      expect(config['lifecycle']['prevent_destroy']).to eq(true)
      expect(config['depends_on']).to eq(['other.resource'])
    end
  end

  describe 'custom block' do
    it 'executes custom block with resource DSL and attrs' do
      synth.extend(TestCustomBlockResource)
      synth.test_custom(:test, { name: 'my-resource', priority: 42 })
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

  describe '.define_data' do
    before(:all) do
      unless defined?(TestDataAttributes)
        TestDataAttributes = Class.new(Pangea::Resources::BaseAttributes) do
          attribute :path, Dry::Types['strict.string']
          attribute :name, Dry::Types['strict.string'].optional.default(nil)
        end
      end

      unless defined?(TestDataSource)
        TestDataSource = Module.new do
          include Pangea::Resources::ResourceBuilder

          define_data :test_data_source,
            attributes_class: TestDataAttributes,
            outputs: { id: :id, value: :value },
            map: [:path],
            map_present: [:name]
        end
      end
    end

    it 'defines a method prefixed with data_' do
      synth.extend(TestDataSource)
      expect(synth).to respond_to(:data_test_data_source)
    end

    it 'creates a data source block in synthesis' do
      synth.extend(TestDataSource)
      synth.data_test_data_source(:my_data, { path: '/secret/path' })
      result = normalize_synthesis(synth.synthesis)

      config = result.dig('data', 'test_data_source', 'my_data')
      expect(config).not_to be_nil
      expect(config['path']).to eq('/secret/path')
    end

    it 'returns ResourceReference with data. prefix in outputs' do
      synth.extend(TestDataSource)
      ref = synth.data_test_data_source(:my_data, { path: '/secret/path' })

      expect(ref).to be_a(Pangea::Resources::ResourceReference)
      expect(ref.type).to eq('data.test_data_source')
      expect(ref.outputs[:id]).to eq('${data.test_data_source.my_data.id}')
      expect(ref.outputs[:value]).to eq('${data.test_data_source.my_data.value}')
    end

    it 'includes map_present attributes when non-nil' do
      synth.extend(TestDataSource)
      synth.data_test_data_source(:my_data, { path: '/path', name: 'named' })
      result = normalize_synthesis(synth.synthesis)

      config = result.dig('data', 'test_data_source', 'my_data')
      expect(config['name']).to eq('named')
    end

    it 'raises ArgumentError for unknown attribute keys' do
      synth.extend(TestDataSource)
      expect {
        synth.data_test_data_source(:my_data, { path: '/path', bogus_key: 'x' })
      }.to raise_error(ArgumentError, /unknown attributes.*bogus_key/)
    end
  end

  describe '.data_definitions' do
    it 'returns empty hash for modules without data definitions' do
      mod = Module.new { include Pangea::Resources::ResourceBuilder }
      expect(mod.data_definitions).to eq({})
    end

    it 'returns metadata for defined data sources' do
      defs = TestDataSource.data_definitions
      expect(defs).to have_key(:test_data_source)
      expect(defs[:test_data_source][:attributes_class]).to eq(TestDataAttributes)
      expect(defs[:test_data_source][:outputs]).to eq({ id: :id, value: :value })
    end
  end
end
