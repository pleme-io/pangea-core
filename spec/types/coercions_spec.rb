# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Pangea::Resources::Types coercion types' do
  describe 'PortString' do
    let(:type) { Pangea::Resources::Types::PortString }

    it 'accepts a String' do
      expect(type['8080']).to eq('8080')
    end

    it 'coerces an Integer to String' do
      expect(type[8080]).to eq('8080')
    end

    it 'accepts traffic-port string' do
      expect(type['traffic-port']).to eq('traffic-port')
    end
  end

  describe 'PortInt' do
    let(:type) { Pangea::Resources::Types::PortInt }

    it 'accepts an Integer' do
      expect(type[443]).to eq(443)
    end

    it 'coerces a String to Integer' do
      expect(type['8080']).to eq(8080)
    end

    it 'accepts port 0' do
      expect(type[0]).to eq(0)
    end

    it 'accepts port 65535' do
      expect(type[65535]).to eq(65535)
    end

    it 'rejects ports above 65535' do
      expect { type[65536] }.to raise_error(Dry::Types::ConstraintError)
    end

    it 'rejects negative ports' do
      expect { type[-1] }.to raise_error(Dry::Types::ConstraintError)
    end
  end

  describe 'CoercibleBool' do
    let(:type) { Pangea::Resources::Types::CoercibleBool }

    it 'accepts true' do
      expect(type[true]).to be true
    end

    it 'accepts false' do
      expect(type[false]).to be false
    end

    it 'coerces "true" string' do
      expect(type['true']).to be true
    end

    it 'coerces "false" string' do
      expect(type['false']).to be false
    end

    it 'coerces "yes" string' do
      expect(type['yes']).to be true
    end

    it 'coerces "no" string' do
      expect(type['no']).to be false
    end

    it 'coerces "1" string' do
      expect(type['1']).to be true
    end

    it 'coerces "0" string' do
      expect(type['0']).to be false
    end

    it 'coerces integer 1' do
      expect(type[1]).to be true
    end

    it 'coerces integer 0' do
      expect(type[0]).to be false
    end

    it 'is case-insensitive for strings' do
      expect(type['TRUE']).to be true
      expect(type['True']).to be true
      expect(type['YES']).to be true
    end
  end
end
