# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Pangea::Contracts::ArchitectureResult do
  let(:config) { double('config', backend: :aws, kubernetes_version: '1.29', region: 'us-east-1') }
  let(:result) { described_class.new(:production, config) }

  describe '#initialize' do
    it 'sets name and config' do
      expect(result.name).to eq(:production)
      expect(result.config).to eq(config)
    end

    it 'starts with nil cluster, network, iam' do
      expect(result.cluster).to be_nil
      expect(result.network).to be_nil
      expect(result.iam).to be_nil
    end

    it 'starts with empty node_pools' do
      expect(result.node_pools).to eq({})
    end
  end

  describe '#cluster=' do
    let(:control_plane_ref) do
      double('cp_ref', id: 'cp-1', arn: 'arn:1', to_h: {}, nlb: nil, sg_id: nil)
    end

    it 'auto-wraps a raw reference in ClusterResult' do
      result.cluster = control_plane_ref
      expect(result.cluster).to be_a(Pangea::Contracts::ClusterResult)
      expect(result.cluster.control_plane_ref).to eq(control_plane_ref)
    end

    it 'accepts a ClusterResult directly without re-wrapping' do
      cluster_result = Pangea::Contracts::ClusterResult.new(control_plane_ref)
      result.cluster = cluster_result
      expect(result.cluster).to eq(cluster_result)
    end

    it 'sets nil when given nil' do
      result.cluster = nil
      expect(result.cluster).to be_nil
    end
  end

  describe '#add_node_pool' do
    it 'adds a node pool by name' do
      pool_ref = double('pool_ref')
      result.add_node_pool(:system, pool_ref)
      expect(result.node_pools[:system]).to eq(pool_ref)
    end

    it 'converts string names to symbols' do
      pool_ref = double('pool_ref')
      result.add_node_pool('worker', pool_ref)
      expect(result.node_pools[:worker]).to eq(pool_ref)
    end
  end

  describe '#method_missing delegation to cluster' do
    let(:control_plane_ref) do
      double('cp_ref', id: 'cp-1', arn: 'arn:1', to_h: {},
             nlb: 'nlb-ref', sg_id: 'sg-1', custom_attr: 'custom-val')
    end

    before { result.cluster = control_plane_ref }

    it 'delegates to cluster for known methods' do
      expect(result.nlb).to eq('nlb-ref')
    end

    it 'delegates custom attributes via method_missing' do
      expect(result.custom_attr).to eq('custom-val')
    end

    it 'raises NoMethodError for truly missing methods' do
      expect { result.nonexistent_method }.to raise_error(NoMethodError)
    end
  end

  describe '#to_h' do
    it 'serializes the result' do
      allow(config).to receive(:respond_to?).and_return(true)
      allow(config).to receive(:managed_kubernetes?).and_return(false)

      hash = result.to_h
      expect(hash[:name]).to eq(:production)
      expect(hash[:backend]).to eq(:aws)
      expect(hash[:kubernetes_version]).to eq('1.29')
      expect(hash[:region]).to eq('us-east-1')
      expect(hash[:cluster]).to be_nil
      expect(hash[:network]).to be_nil
      expect(hash[:iam]).to be_nil
      expect(hash[:node_pools]).to eq({})
    end
  end
end
