# frozen_string_literal: true

require 'pangea/tagging/tag_set'

RSpec.describe Pangea::Tagging::TagSet do
  let(:base_tags) { { ManagedBy: 'pangea', Team: 'platform', Environment: 'dev', Name: 'test-vpc' } }
  let(:tag_set) { described_class.new(base_tags) }

  describe '#initialize' do
    it 'normalizes keys to symbols' do
      ts = described_class.new('ManagedBy' => 'pangea', 'Team' => 'platform')
      expect(ts[:ManagedBy]).to eq('pangea')
    end

    it 'converts values to strings' do
      ts = described_class.new(count: 42, enabled: true)
      expect(ts[:count]).to eq('42')
      expect(ts[:enabled]).to eq('true')
    end

    it 'freezes entries' do
      expect(tag_set.entries).to be_frozen
    end
  end

  describe '#merge' do
    it 'returns a new TagSet with merged tags' do
      merged = tag_set.merge(Cluster: 'prod')
      expect(merged[:Cluster]).to eq('prod')
      expect(merged[:ManagedBy]).to eq('pangea')
    end

    it 'does not mutate the original' do
      tag_set.merge(Cluster: 'prod')
      expect(tag_set.key?(:Cluster)).to be false
    end

    it 'overwrites existing keys' do
      merged = tag_set.merge(Name: 'new-name')
      expect(merged[:Name]).to eq('new-name')
    end
  end

  describe '#to_aws' do
    it 'returns string-keyed hash' do
      result = tag_set.to_aws
      expect(result).to be_a(Hash)
      expect(result.keys).to all(be_a(String))
      expect(result['ManagedBy']).to eq('pangea')
      expect(result['Name']).to eq('test-vpc')
    end
  end

  describe '#to_aws_asg' do
    it 'returns array of key/value/propagate hashes' do
      result = tag_set.to_aws_asg
      expect(result).to be_an(Array)
      expect(result.length).to eq(4)
      entry = result.find { |t| t[:key] == 'ManagedBy' }
      expect(entry[:value]).to eq('pangea')
      expect(entry[:propagate_at_launch]).to be true
    end

    it 'respects propagate: false' do
      result = tag_set.to_aws_asg(propagate: false)
      result.each { |t| expect(t[:propagate_at_launch]).to be false }
    end
  end

  describe '#to_aws_tag_spec' do
    it 'returns array with resource_type and tags' do
      result = tag_set.to_aws_tag_spec
      expect(result).to be_an(Array)
      expect(result.length).to eq(1)
      expect(result[0][:resource_type]).to eq('instance')
      expect(result[0][:tags]).to eq(tag_set.to_aws)
    end

    it 'accepts custom resource_type' do
      result = tag_set.to_aws_tag_spec(resource_type: 'volume')
      expect(result[0][:resource_type]).to eq('volume')
    end
  end

  describe '#to_gcp' do
    it 'lowercases keys and values' do
      result = tag_set.to_gcp
      expect(result.keys).to all(match(/\A[a-z0-9_-]+\z/))
      expect(result['managedby']).to eq('pangea')
    end

    it 'sanitizes special characters to underscores' do
      ts = described_class.new('Special.Key!' => 'Some Value')
      result = ts.to_gcp
      expect(result).to have_key('special_key_')
      expect(result['special_key_']).to eq('some_value')
    end

    it 'truncates keys to 63 characters' do
      ts = described_class.new('a' * 100 => 'b' * 100)
      result = ts.to_gcp
      result.each do |k, v|
        expect(k.length).to be <= 63
        expect(v.length).to be <= 63
      end
    end
  end

  describe '#to_azure' do
    it 'returns same format as AWS' do
      expect(tag_set.to_azure).to eq(tag_set.to_aws)
    end
  end

  describe '#to_hcloud' do
    it 'returns same format as GCP' do
      expect(tag_set.to_hcloud).to eq(tag_set.to_gcp)
    end
  end

  describe '#to_cloudflare' do
    it 'returns array of key:value strings' do
      result = tag_set.to_cloudflare
      expect(result).to be_an(Array)
      expect(result).to include('ManagedBy:pangea')
      expect(result).to include('Name:test-vpc')
    end
  end

  describe '#to_datadog' do
    it 'returns array of key:value strings' do
      result = tag_set.to_datadog
      expect(result).to include('ManagedBy:pangea')
    end
  end

  describe '#to_kubernetes' do
    it 'lowercases keys and preserves / and . characters' do
      ts = described_class.new('app.kubernetes.io/name' => 'my-app', ManagedBy: 'pangea')
      result = ts.to_kubernetes
      expect(result).to have_key('app.kubernetes.io/name')
      expect(result['app.kubernetes.io/name']).to eq('my-app')
      expect(result['managedby']).to eq('pangea')
    end

    it 'replaces invalid characters with dashes' do
      ts = described_class.new('Special!Key' => 'value')
      result = ts.to_kubernetes
      expect(result).to have_key('special-key')
    end
  end

  describe '#to_kubernetes_annotations' do
    it 'returns string-keyed hash without sanitization' do
      ts = described_class.new(ManagedBy: 'pangea', 'Custom.Key!' => 'any value')
      result = ts.to_kubernetes_annotations
      expect(result).to be_a(Hash)
      expect(result['ManagedBy']).to eq('pangea')
      expect(result['Custom.Key!']).to eq('any value')
    end
  end

  describe '#to_vault' do
    it 'returns array of key:value strings' do
      result = tag_set.to_vault
      expect(result).to be_an(Array)
      expect(result).to include('ManagedBy:pangea')
      expect(result).to include('Name:test-vpc')
    end
  end

  describe '#to_mongodbatlas' do
    it 'returns array of {key:, value:} hashes' do
      result = tag_set.to_mongodbatlas
      expect(result).to be_an(Array)
      expect(result.length).to eq(4)
      entry = result.find { |t| t[:key] == 'ManagedBy' }
      expect(entry).not_to be_nil
      expect(entry[:value]).to eq('pangea')
    end

    it 'converts keys and values to strings' do
      ts = described_class.new(count: 42)
      result = ts.to_mongodbatlas
      expect(result.first[:key]).to eq('count')
      expect(result.first[:value]).to eq('42')
    end
  end

  describe '#to_github_labels' do
    it 'returns array of key strings only' do
      result = tag_set.to_github_labels
      expect(result).to be_an(Array)
      expect(result).to include('ManagedBy')
      expect(result).to include('Name')
      expect(result.length).to eq(4)
    end
  end

  describe '#to_consul' do
    it 'returns same format as AWS' do
      expect(tag_set.to_consul).to eq(tag_set.to_aws)
    end
  end

  describe '#to_nomad' do
    it 'returns same format as GCP' do
      expect(tag_set.to_nomad).to eq(tag_set.to_gcp)
    end
  end

  describe '#for_resource' do
    it 'delegates to TagAdapter for AWS resources' do
      result = tag_set.for_resource(:aws_vpc)
      expect(result).to eq({ tags: tag_set.to_aws })
    end

    it 'delegates to TagAdapter for GCP resources' do
      result = tag_set.for_resource(:google_compute_instance)
      expect(result).to eq({ labels: tag_set.to_gcp })
    end

    it 'delegates to TagAdapter for AWS ASG' do
      result = tag_set.for_resource(:aws_autoscaling_group)
      expect(result[:tag]).to be_an(Array)
      expect(result[:tag].first[:propagate_at_launch]).to be true
    end
  end

  describe 'integration with Fingerprint' do
    it 'wraps Fingerprint.tags output' do
      fp = Pangea::Tagging::Fingerprint.new(
        cluster_name: 'test', environment: 'dev', architecture: 'k3s'
      )
      ts = described_class.new(fp.tags)
      expect(ts[:ManagedBy]).to eq('pangea')
      expect(ts[:PangeaFingerprint]).not_to be_nil
      expect(ts.to_aws).to have_key('PangeaFingerprint')
      expect(ts.to_aws_asg.find { |t| t[:key] == 'PangeaFingerprint' }).not_to be_nil
    end
  end
end
