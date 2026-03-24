# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Pangea::Contracts::ClusterResult do
  # Stub control plane reference with the methods ClusterResult expects
  let(:control_plane_ref) do
    double('control_plane_ref',
           nlb: 'nlb-ref',
           asg: 'asg-ref',
           lt: 'lt-ref',
           tg: 'tg-ref',
           listener: 'listener-ref',
           sg_id: 'sg-12345',
           id: 'cluster-id',
           arn: 'arn:aws:cluster',
           to_h: { id: 'cluster-id' },
           custom_method: 'custom-value')
  end

  let(:result) { described_class.new(control_plane_ref) }

  describe '#initialize' do
    it 'stores the control_plane_ref' do
      expect(result.control_plane_ref).to eq(control_plane_ref)
    end
  end

  describe 'named accessors' do
    it 'delegates nlb' do
      expect(result.nlb).to eq('nlb-ref')
    end

    it 'delegates asg' do
      expect(result.asg).to eq('asg-ref')
    end

    it 'delegates launch_template / lt' do
      expect(result.launch_template).to eq('lt-ref')
      expect(result.lt).to eq('lt-ref')
    end

    it 'delegates target_group / tg' do
      expect(result.target_group).to eq('tg-ref')
      expect(result.tg).to eq('tg-ref')
    end

    it 'delegates listener' do
      expect(result.listener).to eq('listener-ref')
    end

    it 'delegates sg_id' do
      expect(result.sg_id).to eq('sg-12345')
    end

    it 'delegates id' do
      expect(result.id).to eq('cluster-id')
    end

    it 'delegates arn' do
      expect(result.arn).to eq('arn:aws:cluster')
    end
  end

  describe '#security_group' do
    it 'returns a SecurityGroupAccessor wrapping sg_id' do
      sg = result.security_group
      expect(sg).to be_a(Pangea::Contracts::SecurityGroupAccessor)
      expect(sg.id).to eq('sg-12345')
    end
  end

  describe '#to_h' do
    it 'delegates to control_plane_ref.to_h' do
      expect(result.to_h).to eq(id: 'cluster-id')
    end

    it 'returns empty hash when control_plane_ref has no to_h' do
      bare_ref = double('bare', nlb: nil, sg_id: nil, id: nil, arn: nil)
      bare_result = described_class.new(bare_ref)
      expect(bare_result.to_h).to eq({})
    end
  end

  describe '#method_missing delegation' do
    it 'forwards unknown methods to control_plane_ref' do
      expect(result.custom_method).to eq('custom-value')
    end

    it 'raises NoMethodError for truly missing methods' do
      expect { result.nonexistent_method }.to raise_error(NoMethodError)
    end
  end

  describe '#respond_to_missing?' do
    it 'returns true for methods the control_plane_ref supports' do
      expect(result.respond_to?(:custom_method)).to be true
    end

    it 'returns false for methods the control_plane_ref does not support' do
      expect(result.respond_to?(:nonexistent_method)).to be false
    end
  end
end
