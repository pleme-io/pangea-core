# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Pangea::Resources::Validators::Common do
  let(:klass) do
    Class.new do
      include Pangea::Resources::Validators::Common
    end
  end

  let(:instance) { klass.new }

  let(:attrs_class) do
    Class.new(Pangea::Resources::BaseAttributes) do
      attribute :field_a, Pangea::Resources::Types::String.optional.default(nil)
      attribute :field_b, Pangea::Resources::Types::String.optional.default(nil)
      attribute :field_c, Pangea::Resources::Types::String.optional.default(nil)
    end
  end

  describe '#check_mutually_exclusive' do
    it 'passes when only one field is present' do
      attrs = attrs_class.new(field_a: 'value')
      expect { instance.check_mutually_exclusive(attrs, :field_a, :field_b) }.not_to raise_error
    end

    it 'passes when no fields are present' do
      attrs = attrs_class.new
      expect { instance.check_mutually_exclusive(attrs, :field_a, :field_b) }.not_to raise_error
    end

    it 'raises when multiple mutually exclusive fields are present' do
      attrs = attrs_class.new(field_a: 'val1', field_b: 'val2')
      expect { instance.check_mutually_exclusive(attrs, :field_a, :field_b) }.to raise_error(Dry::Struct::Error, /Cannot specify both/)
    end

    it 'raises listing all conflicting fields' do
      attrs = attrs_class.new(field_a: 'v1', field_b: 'v2', field_c: 'v3')
      expect { instance.check_mutually_exclusive(attrs, :field_a, :field_b, :field_c) }.to raise_error(Dry::Struct::Error)
    end
  end

  describe '#check_required_one_of' do
    it 'passes when at least one field is present' do
      attrs = attrs_class.new(field_a: 'value')
      expect { instance.check_required_one_of(attrs, :field_a, :field_b) }.not_to raise_error
    end

    it 'raises when no fields are present' do
      attrs = attrs_class.new
      expect { instance.check_required_one_of(attrs, :field_a, :field_b) }.to raise_error(Dry::Struct::Error, /Must specify one of/)
    end
  end

  describe '#skip_validation_for_refs?' do
    it 'returns true when a field contains a terraform reference' do
      attrs = attrs_class.new(field_a: '${aws_vpc.main.id}')
      expect(instance.skip_validation_for_refs?(attrs, :field_a)).to be true
    end

    it 'returns false when no fields contain terraform references' do
      attrs = attrs_class.new(field_a: 'plain-value')
      expect(instance.skip_validation_for_refs?(attrs, :field_a)).to be false
    end

    it 'returns true when any of the specified fields has a reference' do
      attrs = attrs_class.new(field_a: 'plain', field_b: '${data.resource.name.attr}')
      expect(instance.skip_validation_for_refs?(attrs, :field_a, :field_b)).to be true
    end

    it 'returns false for nil fields' do
      attrs = attrs_class.new
      expect(instance.skip_validation_for_refs?(attrs, :field_a)).to be false
    end
  end
end
