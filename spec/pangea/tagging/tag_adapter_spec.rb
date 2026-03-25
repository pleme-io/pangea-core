# frozen_string_literal: true

require 'pangea/tagging/tag_set'
require 'pangea/tagging/tag_adapter'

RSpec.describe Pangea::Tagging::TagAdapter do
  let(:tag_set) { Pangea::Tagging::TagSet.new(ManagedBy: 'pangea', Name: 'test') }

  describe '.format_for' do
    it 'returns AWS ASG format for aws_autoscaling_group' do
      fmt = described_class.format_for(:aws_autoscaling_group)
      expect(fmt[:method]).to eq(:to_aws_asg)
      expect(fmt[:attr]).to eq(:tag)
    end

    it 'returns AWS tag spec format for aws_launch_template' do
      fmt = described_class.format_for(:aws_launch_template)
      expect(fmt[:method]).to eq(:to_aws_tag_spec)
      expect(fmt[:attr]).to eq(:tag_specifications)
    end

    it 'returns AWS format for generic aws_ resources' do
      %i[aws_vpc aws_subnet aws_security_group aws_s3_bucket aws_iam_role].each do |rt|
        fmt = described_class.format_for(rt)
        expect(fmt[:method]).to eq(:to_aws)
        expect(fmt[:attr]).to eq(:tags)
      end
    end

    it 'returns Azure format for azurerm_ resources' do
      fmt = described_class.format_for(:azurerm_resource_group)
      expect(fmt[:method]).to eq(:to_azure)
      expect(fmt[:attr]).to eq(:tags)
    end

    it 'returns GCP format for google_ resources' do
      fmt = described_class.format_for(:google_compute_instance)
      expect(fmt[:method]).to eq(:to_gcp)
      expect(fmt[:attr]).to eq(:labels)
    end

    it 'returns Hcloud format for hcloud_ resources' do
      fmt = described_class.format_for(:hcloud_server)
      expect(fmt[:method]).to eq(:to_hcloud)
      expect(fmt[:attr]).to eq(:labels)
    end

    it 'returns Kubernetes format for kubernetes_ resources' do
      fmt = described_class.format_for(:kubernetes_deployment)
      expect(fmt[:method]).to eq(:to_kubernetes)
      expect(fmt[:attr]).to eq(:labels)
    end

    it 'returns Datadog format for datadog_ resources' do
      fmt = described_class.format_for(:datadog_monitor)
      expect(fmt[:method]).to eq(:to_datadog)
      expect(fmt[:attr]).to eq(:tags)
    end

    it 'returns Cloudflare format for cloudflare_ resources' do
      fmt = described_class.format_for(:cloudflare_record)
      expect(fmt[:method]).to eq(:to_cloudflare)
      expect(fmt[:attr]).to eq(:tags)
    end

    it 'returns Vault format for vault_ resources' do
      fmt = described_class.format_for(:vault_generic_secret)
      expect(fmt[:method]).to eq(:to_vault)
      expect(fmt[:attr]).to eq(:tags)
    end

    it 'returns MongoDBAtlas format for mongodbatlas_ resources' do
      fmt = described_class.format_for(:mongodbatlas_cluster)
      expect(fmt[:method]).to eq(:to_mongodbatlas)
      expect(fmt[:attr]).to eq(:tags)
    end

    it 'returns Consul format for consul_ resources' do
      fmt = described_class.format_for(:consul_service)
      expect(fmt[:method]).to eq(:to_consul)
      expect(fmt[:attr]).to eq(:tags)
    end

    it 'returns Nomad format for nomad_ resources' do
      fmt = described_class.format_for(:nomad_job)
      expect(fmt[:method]).to eq(:to_nomad)
      expect(fmt[:attr]).to eq(:meta)
    end

    it 'falls back to AWS format for unknown resources' do
      fmt = described_class.format_for(:some_unknown_resource)
      expect(fmt[:method]).to eq(:to_aws)
      expect(fmt[:attr]).to eq(:tags)
    end
  end

  describe '.format_for ordering' do
    it 'matches aws_autoscaling_group before generic aws_' do
      fmt = described_class.format_for(:aws_autoscaling_group)
      expect(fmt[:method]).to eq(:to_aws_asg)
    end

    it 'matches aws_launch_template before generic aws_' do
      fmt = described_class.format_for(:aws_launch_template)
      expect(fmt[:method]).to eq(:to_aws_tag_spec)
    end

    it 'matches generic aws_ for non-special aws resources' do
      fmt = described_class.format_for(:aws_instance)
      expect(fmt[:method]).to eq(:to_aws)
    end
  end

  describe '.transform' do
    it 'transforms tags for AWS resources' do
      result = described_class.transform(tag_set, :aws_vpc)
      expect(result).to eq({ tags: { 'ManagedBy' => 'pangea', 'Name' => 'test' } })
    end

    it 'transforms tags for AWS ASG resources' do
      result = described_class.transform(tag_set, :aws_autoscaling_group)
      expect(result[:tag]).to be_an(Array)
      expect(result[:tag].length).to eq(2)
      entry = result[:tag].find { |t| t[:key] == 'ManagedBy' }
      expect(entry[:value]).to eq('pangea')
      expect(entry[:propagate_at_launch]).to be true
    end

    it 'transforms tags for AWS Launch Template' do
      result = described_class.transform(tag_set, :aws_launch_template)
      expect(result[:tag_specifications]).to be_an(Array)
      expect(result[:tag_specifications].first[:resource_type]).to eq('instance')
      expect(result[:tag_specifications].first[:tags]).to eq({ 'ManagedBy' => 'pangea', 'Name' => 'test' })
    end

    it 'transforms tags for GCP resources' do
      result = described_class.transform(tag_set, :google_compute_instance)
      expect(result[:labels]).to eq({ 'managedby' => 'pangea', 'name' => 'test' })
    end

    it 'transforms tags for Hcloud resources' do
      result = described_class.transform(tag_set, :hcloud_server)
      expect(result[:labels]).to eq({ 'managedby' => 'pangea', 'name' => 'test' })
    end

    it 'transforms tags for Kubernetes resources' do
      result = described_class.transform(tag_set, :kubernetes_deployment)
      expect(result[:labels]).to be_a(Hash)
      expect(result[:labels]['managedby']).to eq('pangea')
    end

    it 'transforms tags for Datadog resources' do
      result = described_class.transform(tag_set, :datadog_monitor)
      expect(result[:tags]).to be_an(Array)
      expect(result[:tags]).to include('ManagedBy:pangea')
    end

    it 'transforms tags for Cloudflare resources' do
      result = described_class.transform(tag_set, :cloudflare_record)
      expect(result[:tags]).to be_an(Array)
      expect(result[:tags]).to include('ManagedBy:pangea')
    end

    it 'transforms tags for Vault resources' do
      result = described_class.transform(tag_set, :vault_generic_secret)
      expect(result[:tags]).to be_an(Array)
      expect(result[:tags]).to include('ManagedBy:pangea')
    end

    it 'transforms tags for MongoDBAtlas resources' do
      result = described_class.transform(tag_set, :mongodbatlas_cluster)
      expect(result[:tags]).to be_an(Array)
      entry = result[:tags].find { |t| t[:key] == 'ManagedBy' }
      expect(entry[:value]).to eq('pangea')
    end

    it 'transforms tags for Consul resources' do
      result = described_class.transform(tag_set, :consul_service)
      expect(result[:tags]).to eq({ 'ManagedBy' => 'pangea', 'Name' => 'test' })
    end

    it 'transforms tags for Nomad resources' do
      result = described_class.transform(tag_set, :nomad_job)
      expect(result[:meta]).to eq({ 'managedby' => 'pangea', 'name' => 'test' })
    end

    it 'transforms tags for unknown resources using fallback' do
      result = described_class.transform(tag_set, :some_unknown_resource)
      expect(result[:tags]).to eq({ 'ManagedBy' => 'pangea', 'Name' => 'test' })
    end

    it 'returns empty hash when tag_set is nil' do
      result = described_class.transform(nil, :aws_vpc)
      expect(result).to eq({})
    end
  end
end
