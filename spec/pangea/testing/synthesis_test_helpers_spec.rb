# frozen_string_literal: true

require 'spec_helper'
require 'pangea/testing'

RSpec.describe Pangea::Testing::SynthesisTestHelpers do
  include described_class

  describe '#create_synthesizer' do
    it 'creates a synthesizer instance' do
      synth = create_synthesizer
      # Should be either TerraformSynthesizer or MockTerraformSynthesizer
      expect(synth).to respond_to(:synthesis)
    end
  end

  describe '#normalize_synthesis' do
    it 'converts symbol keys to strings via JSON round-trip' do
      input = { resource: { aws_vpc: { main: { cidr: '10.0.0.0/16' } } } }
      result = normalize_synthesis(input)
      expect(result).to have_key('resource')
      expect(result['resource']).to have_key('aws_vpc')
    end
  end

  describe '#validate_terraform_structure' do
    it 'validates resource structure' do
      result = { 'resource' => { 'aws_vpc' => {} } }
      expect { validate_terraform_structure(result, :resource) }.not_to raise_error
    end

    it 'validates data_source structure' do
      result = { 'data' => { 'aws_ami' => {} } }
      expect { validate_terraform_structure(result, :data_source) }.not_to raise_error
    end

    it 'validates output structure' do
      result = { 'output' => { 'vpc_id' => {} } }
      expect { validate_terraform_structure(result, :output) }.not_to raise_error
    end
  end

  describe '#validate_resource_references' do
    it 'extracts terraform references from result' do
      result = {
        'resource' => {
          'aws_subnet' => {
            'main' => { 'vpc_id' => '${aws_vpc.main.id}' }
          }
        }
      }
      refs = validate_resource_references(result)
      expect(refs).to include('${aws_vpc.main.id}')
    end

    it 'returns empty array when no references exist' do
      result = { 'resource' => { 'aws_vpc' => { 'main' => { 'cidr' => '10.0.0.0/16' } } } }
      refs = validate_resource_references(result)
      expect(refs).to be_empty
    end
  end

  describe '#validate_resource_structure' do
    it 'validates and returns resource config' do
      result = {
        'resource' => {
          'aws_vpc' => {
            'main' => { 'cidr_block' => '10.0.0.0/16' }
          }
        }
      }
      config = validate_resource_structure(result, 'aws_vpc', 'main')
      expect(config).to eq({ 'cidr_block' => '10.0.0.0/16' })
    end
  end

  describe '#validate_resource_attributes' do
    it 'validates string attributes' do
      config = { 'name' => 'test' }
      expect { validate_resource_attributes(config, { name: String }) }.not_to raise_error
    end

    it 'validates integer attributes' do
      config = { 'count' => 5 }
      expect { validate_resource_attributes(config, { count: Integer }) }.not_to raise_error
    end

    it 'validates boolean attributes' do
      config = { 'enabled' => true }
      expect { validate_resource_attributes(config, { enabled: true }) }.not_to raise_error
    end

    it 'validates array attributes' do
      config = { 'items' => [1, 2, 3] }
      expect { validate_resource_attributes(config, { items: Array }) }.not_to raise_error
    end

    it 'validates hash attributes' do
      config = { 'tags' => { 'Name' => 'test' } }
      expect { validate_resource_attributes(config, { tags: Hash }) }.not_to raise_error
    end

    it 'skips missing attributes' do
      config = {}
      expect { validate_resource_attributes(config, { name: String }) }.not_to raise_error
    end
  end

  describe '#validate_required_attributes' do
    it 'passes when all required attributes are present' do
      config = { 'name' => 'test', 'cidr' => '10.0.0.0/16' }
      expect { validate_required_attributes(config, %w[name cidr]) }.not_to raise_error
    end

    it 'fails when a required attribute is missing' do
      config = { 'name' => 'test' }
      expect { validate_required_attributes(config, %w[name cidr]) }.to raise_error(RSpec::Expectations::ExpectationNotMetError)
    end
  end

  describe '#validate_dependency_ordering' do
    it 'passes when all dependencies are defined' do
      result = {
        'resource' => {
          'aws_vpc' => {
            'main' => { 'cidr' => '10.0.0.0/16' }
          },
          'aws_subnet' => {
            'public' => { 'vpc_id' => '${aws_vpc.main.id}' }
          }
        }
      }
      expect { validate_dependency_ordering(result) }.not_to raise_error
    end

    it 'fails when a dependency is not defined' do
      result = {
        'resource' => {
          'aws_subnet' => {
            'public' => { 'vpc_id' => '${aws_vpc.main.id}' }
          }
        }
      }
      expect { validate_dependency_ordering(result) }.to raise_error(RSpec::Expectations::ExpectationNotMetError)
    end
  end

  describe '#synthesize_and_validate' do
    it 'creates, synthesizes, and validates in one call' do
      result = synthesize_and_validate(:resource, normalize: true) do
        resource :aws_vpc, :main do
          cidr_block '10.0.0.0/16'
        end
      end
      expect(result).to be_a(Hash)
      expect(result).to have_key('resource')
    end
  end

  describe '#reset_terraform_synthesizer_state' do
    it 'is a no-op method' do
      expect { reset_terraform_synthesizer_state }.not_to raise_error
    end
  end

  describe '#cleanup_test_resources' do
    it 'is a no-op method' do
      expect { cleanup_test_resources }.not_to raise_error
    end
  end
end
