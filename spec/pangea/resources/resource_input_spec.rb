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

  # Mirrors hcloud_firewall_attachment: an id list typed as numbers whose
  # real-world values are ${...} refs to servers built in the same workspace.
  class NumericArrayAttributes < Pangea::Resources::BaseAttributes
    T = TestTypes
    attribute :firewall_id, (T::Coercible::Integer | T::Coercible::Float)
    attribute? :server_ids, T::Array.of((T::Coercible::Integer | T::Coercible::Float)).optional
  end

  # Containers refs can hide inside at depth: nested arrays, blocks-as-hashes,
  # and typed maps.
  class NestedAttributes < Pangea::Resources::BaseAttributes
    T = TestTypes
    attribute :name, T::String
    attribute? :matrix, T::Array.of(T::Array.of(T::Integer)).optional
    attribute? :network, T::Array.of(T::Hash).optional
    attribute? :weights, T::Hash.map(T::String, T::Integer).optional
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

  # ── 2b. Refs nested INSIDE containers ───────────────────────────
  #
  # A ref is opaque at whatever depth it sits. `server_ids: [srv.id, srv.id]`
  # is exactly as unresolvable at synthesis time as `firewall_id: fw.id` —
  # the only difference is that the unknown is an element rather than the
  # whole value. Everything AROUND the ref is still known and still checked.

  describe 'refs nested inside containers' do
    let(:srv_a) { '${hcloud_server.a.id}' }
    let(:srv_b) { '${hcloud_server.b.id}' }

    it 'partitions an array whose elements are all refs' do
      input = described_class.partition(TestTypes::NumericArrayAttributes, {
        firewall_id: '${hcloud_firewall.main.id}',
        server_ids: [srv_a, srv_b],
      })
      expect(input.refs[:server_ids]).to eq([srv_a, srv_b])
      expect(input[:server_ids]).to eq([srv_a, srv_b])
    end

    it 'passes an array of refs through to_h verbatim, order preserved' do
      input = described_class.partition(TestTypes::NumericArrayAttributes, {
        firewall_id: 42,
        server_ids: [srv_b, srv_a],
      })
      expect(input.to_h[:server_ids]).to eq([srv_b, srv_a])
      expect(input.to_h[:firewall_id]).to eq(42)
    end

    it 'accepts a MIXED array of refs and valid literals' do
      input = described_class.partition(TestTypes::NumericArrayAttributes, {
        firewall_id: 42,
        server_ids: [srv_a, '12345'],
      })
      expect(input[:server_ids]).to eq([srv_a, '12345'])
    end

    it 'still type-checks the LITERAL elements of a mixed array' do
      expect {
        described_class.partition(TestTypes::NumericArrayAttributes, {
          firewall_id: 42,
          server_ids: [srv_a, 'not-a-number'],
        })
      }.to raise_error(/server_ids/)
    end

    it 'partitions refs nested in an array of arrays' do
      input = described_class.partition(TestTypes::NestedAttributes, {
        name: 'n',
        matrix: [[1, 2], ['${var.x}', 4]],
      })
      expect(input.refs).to have_key(:matrix)
      expect(input[:matrix]).to eq([[1, 2], ['${var.x}', 4]])
    end

    it 'still type-checks literal leaves of a nested array' do
      expect {
        described_class.partition(TestTypes::NestedAttributes, {
          name: 'n',
          matrix: [['${var.x}', 'nope']],
        })
      }.to raise_error(/matrix/)
    end

    it 'partitions refs nested inside a block-shaped hash element' do
      input = described_class.partition(TestTypes::NestedAttributes, {
        name: 'n',
        network: [{ network_id: '${hcloud_network.main.id}' }],
      })
      expect(input.refs).to have_key(:network)
      expect(input[:network]).to eq([{ network_id: '${hcloud_network.main.id}' }])
    end

    it 'partitions a typed map holding a ref value' do
      input = described_class.partition(TestTypes::NestedAttributes, {
        name: 'n',
        weights: { 'a' => '${var.w}', 'b' => 2 },
      })
      expect(input.refs).to have_key(:weights)
      expect(input[:weights]).to eq({ 'a' => '${var.w}', 'b' => 2 })
    end

    it 'still type-checks the non-ref values of a typed map' do
      expect {
        described_class.partition(TestTypes::NestedAttributes, {
          name: 'n',
          weights: { 'a' => '${var.w}', 'b' => 'nope' },
        })
      }.to raise_error(/weights/)
    end

    it 'counts an array-of-refs as satisfying required coverage' do
      expect {
        described_class.partition(TestTypes::ArrayAttributes, {
          domain: 'pleme.lol',
          nameservers: ['${a.b.c}', '${d.e.f}'],
        })
      }.not_to raise_error
    end
  end

  # ── 2c. Containment must NOT over-broaden the bypass ────────────

  describe 'ref-free containers keep full validation' do
    it 'routes a ref-free array to literals, not refs' do
      input = described_class.partition(TestTypes::NumericArrayAttributes, {
        firewall_id: 42,
        server_ids: [1, 2],
      })
      expect(input.refs).to be_empty
      expect(input[:server_ids]).to eq([1, 2])
    end

    it 'rejects a ref-free array with a bad element' do
      expect {
        described_class.partition(TestTypes::NumericArrayAttributes, {
          firewall_id: 42,
          server_ids: [1, 'not-a-number'],
        })
      }.to raise_error(Dry::Types::CoercionError)
    end

    it 'rejects an array holding a PARTIAL-ref string (not a real ref)' do
      expect {
        described_class.partition(TestTypes::NumericArrayAttributes, {
          firewall_id: 42,
          server_ids: ['prefix${x.y}'],
        })
      }.to raise_error(/server_ids/)
    end

    it 'rejects a ref-free typed map with a bad value' do
      expect {
        described_class.partition(TestTypes::NestedAttributes, {
          name: 'n',
          weights: { 'a' => 'nope' },
        })
      }.to raise_error(Dry::Types::MapError, /weights/)
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
