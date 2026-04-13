# frozen_string_literal: true

require 'spec_helper'
require 'set'

# Test fixtures — pure types, no ref awareness
module TestTypes
  include Dry.Types()

  class SimpleAttributes < Pangea::Resources::BaseAttributes
    T = TestTypes
    attribute :name, T::String
    attribute? :description, T::String.optional
  end

  class StrictAttributes < Pangea::Resources::BaseAttributes
    T = TestTypes
    CidrBlock = T::String.constrained(format: /\A\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}\/\d{1,2}\z/)
    attribute :cidr, CidrBlock
    attribute :port, T::Integer
  end

  class ArrayAttributes < Pangea::Resources::BaseAttributes
    T = TestTypes
    attribute :domain, T::String
    attribute :nameservers, T::Array.of(T::String)
  end

  class AllOptionalAttributes < Pangea::Resources::BaseAttributes
    T = TestTypes
    attribute? :tag, T::String.optional
    attribute? :count, T::Integer.optional
  end
end

RSpec.describe Pangea::Resources::ResourceInput do
  let(:ref) { '${aws_vpc.main.id}' }
  let(:zone_ref) { '${aws_route53_zone.main.name_servers}' }

  # ── 1. Literal values are validated strictly ────────────────────

  describe 'strict literal validation' do
    it 'accepts valid literals' do
      input = described_class.partition(TestTypes::StrictAttributes, {
        cidr: '10.0.0.0/16',
        port: 443,
      })
      expect(input[:cidr]).to eq('10.0.0.0/16')
      expect(input[:port]).to eq(443)
    end

    it 'rejects invalid CIDR format' do
      expect {
        described_class.partition(TestTypes::StrictAttributes, {
          cidr: 'not-a-cidr',
          port: 443,
        })
      }.to raise_error(Dry::Types::ConstraintError)
    end

    it 'rejects wrong type (string where integer expected)' do
      expect {
        described_class.partition(TestTypes::StrictAttributes, {
          cidr: '10.0.0.0/16',
          port: 'abc',
        })
      }.to raise_error(Dry::Types::ConstraintError, /port/)
    end
  end

  # ── 2. Terraform refs bypass validation transparently ───────────

  describe 'transparent ref bypass' do
    it 'partitions ref on string field' do
      input = described_class.partition(TestTypes::SimpleAttributes, {
        name: ref,
      })
      expect(input.refs[:name]).to eq(ref)
      expect(input.validated.to_h).not_to have_key(:name)
    end

    it 'partitions ref on array field' do
      input = described_class.partition(TestTypes::ArrayAttributes, {
        domain: 'pleme.lol',
        nameservers: zone_ref,
      })
      expect(input.refs[:nameservers]).to eq(zone_ref)
      expect(input[:domain]).to eq('pleme.lol')
      expect(input[:nameservers]).to eq(zone_ref)
    end

    it 'partitions ref on integer field' do
      input = described_class.partition(TestTypes::StrictAttributes, {
        cidr: '10.0.0.0/16',
        port: '${var.port}',
      })
      expect(input.refs[:port]).to eq('${var.port}')
      expect(input[:cidr]).to eq('10.0.0.0/16')
    end
  end

  # ── 3. Random strings are NOT treated as refs ───────────────────

  describe 'ref pattern strictness' do
    it 'treats plain strings as literals' do
      input = described_class.partition(TestTypes::SimpleAttributes, {
        name: 'hello',
      })
      expect(input.refs).to be_empty
      expect(input[:name]).to eq('hello')
    end

    it 'rejects strings with partial ref syntax as literals' do
      input = described_class.partition(TestTypes::SimpleAttributes, {
        name: 'contains ${partial} ref',
      })
      expect(input.refs).to be_empty
      expect(input[:name]).to eq('contains ${partial} ref')
    end

    it 'treats escaped dollar as literal' do
      input = described_class.partition(TestTypes::SimpleAttributes, {
        name: '$${escaped}',
      })
      expect(input.refs).to be_empty
    end

    it 'only accepts full ${...} match as ref' do
      # Must start with ${ and end with }
      expect('${valid.ref}'.match?(described_class::REF_PATTERN)).to be true
      expect('prefix${ref}'.match?(described_class::REF_PATTERN)).to be false
      expect('${ref}suffix'.match?(described_class::REF_PATTERN)).to be false
      expect('plain string'.match?(described_class::REF_PATTERN)).to be false
      expect('${}'.match?(described_class::REF_PATTERN)).to be false  # empty ref
    end
  end

  # ── 4. Required coverage enforced ───────────────────────────────

  describe 'required attribute coverage' do
    it 'accepts all required as literals' do
      expect {
        described_class.partition(TestTypes::SimpleAttributes, { name: 'test' })
      }.not_to raise_error
    end

    it 'accepts all required as refs' do
      expect {
        described_class.partition(TestTypes::SimpleAttributes, { name: ref })
      }.not_to raise_error
    end

    it 'accepts mix of literal + ref required' do
      expect {
        described_class.partition(TestTypes::ArrayAttributes, {
          domain: 'pleme.lol',
          nameservers: zone_ref,
        })
      }.not_to raise_error
    end

    it 'raises when required field missing from BOTH literals and refs' do
      expect {
        described_class.partition(TestTypes::SimpleAttributes, {})
      }.to raise_error(ArgumentError, /missing required attributes.*:name/)
    end

    it 'raises with descriptive message listing all missing fields' do
      expect {
        described_class.partition(TestTypes::ArrayAttributes, {})
      }.to raise_error(ArgumentError, /missing required attributes/)
    end
  end

  # ── 5. [] accessor resolves correctly ───────────────────────────

  describe '[] accessor' do
    it 'returns literal value when no ref' do
      input = described_class.partition(TestTypes::SimpleAttributes, { name: 'test' })
      expect(input[:name]).to eq('test')
    end

    it 'returns ref when field is a ref' do
      input = described_class.partition(TestTypes::SimpleAttributes, { name: ref })
      expect(input[:name]).to eq(ref)
    end

    it 'returns nil for absent optional fields' do
      input = described_class.partition(TestTypes::AllOptionalAttributes, {})
      expect(input[:tag]).to be_nil
    end

    it 'accepts string keys' do
      input = described_class.partition(TestTypes::SimpleAttributes, { name: 'test' })
      expect(input['name']).to eq('test')
    end
  end

  # ── 6. to_h merges correctly ────────────────────────────────────

  describe '#to_h' do
    it 'merges literals and refs' do
      input = described_class.partition(TestTypes::ArrayAttributes, {
        domain: 'pleme.lol',
        nameservers: zone_ref,
      })
      h = input.to_h
      expect(h[:domain]).to eq('pleme.lol')
      expect(h[:nameservers]).to eq(zone_ref)
    end

    it 'includes all fields' do
      input = described_class.partition(TestTypes::SimpleAttributes, {
        name: 'test',
        description: 'desc',
      })
      expect(input.to_h.keys).to contain_exactly(:name, :description)
    end
  end

  # ── 7. Immutability ─────────────────────────────────────────────

  describe 'immutability' do
    it 'ResourceInput is frozen' do
      input = described_class.partition(TestTypes::SimpleAttributes, { name: 'test' })
      expect(input).to be_frozen
    end

    it 'refs hash is frozen' do
      input = described_class.partition(TestTypes::SimpleAttributes, { name: ref })
      expect(input.refs).to be_frozen
    end

    it 'cannot assign new instance variables' do
      input = described_class.partition(TestTypes::SimpleAttributes, { name: 'test' })
      expect { input.instance_variable_set(:@hack, true) }.to raise_error(FrozenError)
    end
  end
end
