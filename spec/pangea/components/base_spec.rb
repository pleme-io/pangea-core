# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Pangea::Components do
  describe Pangea::Components::Networking do
    let(:klass) do
      Class.new do
        include Pangea::Components::Networking
      end
    end

    let(:instance) { klass.new }

    describe '#calculate_subnet_cidr' do
      it 'calculates first subnet CIDR' do
        result = instance.calculate_subnet_cidr('10.0.0.0/16', 0)
        expect(result).to eq('10.0.0.0/24')
      end

      it 'calculates subsequent subnet CIDRs' do
        result = instance.calculate_subnet_cidr('10.0.0.0/16', 1)
        expect(result).to eq('10.0.1.0/24')
      end

      it 'calculates with custom new_bits' do
        result = instance.calculate_subnet_cidr('10.0.0.0/16', 0, 4)
        expect(result).to eq('10.0.0.0/20')
      end

      it 'handles larger subnets' do
        result = instance.calculate_subnet_cidr('172.16.0.0/12', 0, 8)
        expect(result).to eq('172.16.0.0/20')
      end
    end
  end

  describe Pangea::Components::Naming do
    let(:klass) do
      Class.new do
        include Pangea::Components::Naming
      end
    end

    let(:instance) { klass.new }

    describe '#component_resource_name' do
      it 'joins component name and resource type' do
        expect(instance.component_resource_name('web', 'vpc')).to eq(:web_vpc)
      end

      it 'includes suffix when provided' do
        expect(instance.component_resource_name('web', 'subnet', 'private')).to eq(:web_subnet_private)
      end

      it 'returns a symbol' do
        result = instance.component_resource_name('app', 'sg')
        expect(result).to be_a(Symbol)
      end
    end
  end

  describe Pangea::Components::Tagging do
    let(:klass) do
      Class.new do
        include Pangea::Components::Tagging
      end
    end

    let(:instance) { klass.new }

    describe '#merge_tags' do
      it 'merges default and user tags' do
        result = instance.merge_tags({ env: 'dev' }, { team: 'platform' })
        expect(result).to eq({ env: 'dev', team: 'platform' })
      end

      it 'user tags override defaults' do
        result = instance.merge_tags({ env: 'dev' }, { env: 'prod' })
        expect(result).to eq({ env: 'prod' })
      end

      it 'defaults user_tags to empty hash' do
        result = instance.merge_tags({ env: 'dev' })
        expect(result).to eq({ env: 'dev' })
      end
    end
  end

  describe Pangea::Components::Base do
    let(:klass) do
      Class.new do
        include Pangea::Components::Base
      end
    end

    let(:instance) { klass.new }

    describe '#validate_required_attributes' do
      it 'passes when all required attributes present' do
        expect {
          instance.validate_required_attributes({ cidr: '10.0.0.0/16', name: 'vpc' }, [:cidr, :name])
        }.not_to raise_error
      end

      it 'raises for missing required attributes' do
        expect {
          instance.validate_required_attributes({ name: 'vpc' }, [:cidr, :name])
        }.to raise_error(Pangea::Components::ValidationError, /Missing required.*cidr/)
      end
    end

    describe '#component_outputs' do
      it 'wraps resources and computed in hash' do
        result = instance.component_outputs({ vpc: 'vpc-123' }, { count: 3 })
        expect(result[:resources]).to eq({ vpc: 'vpc-123' })
        expect(result[:computed]).to eq({ count: 3 })
        expect(result[:created_at]).to be_a(String)
      end

      it 'defaults computed to empty hash' do
        result = instance.component_outputs({ vpc: 'vpc-123' })
        expect(result[:computed]).to eq({})
      end
    end

    it 'includes Networking, Naming, and Tagging' do
      expect(instance).to respond_to(:calculate_subnet_cidr)
      expect(instance).to respond_to(:component_resource_name)
      expect(instance).to respond_to(:merge_tags)
    end
  end

  describe 'error classes' do
    it 'ComponentError inherits from StandardError' do
      expect(Pangea::Components::ComponentError.superclass).to eq(StandardError)
    end

    it 'ValidationError inherits from ComponentError' do
      expect(Pangea::Components::ValidationError.superclass).to eq(Pangea::Components::ComponentError)
    end

    it 'CompositionError inherits from ComponentError' do
      expect(Pangea::Components::CompositionError.superclass).to eq(Pangea::Components::ComponentError)
    end
  end
end
