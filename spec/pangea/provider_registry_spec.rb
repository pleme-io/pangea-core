# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Pangea::ProviderRegistry do
  describe '.provider_name_for' do
    it 'takes the prefix before the first underscore' do
      expect(described_class.provider_name_for('github_repository')).to eq('github')
      expect(described_class.provider_name_for('github_branch_protection')).to eq('github')
      expect(described_class.provider_name_for('aws_s3_bucket')).to eq('aws')
    end

    it 'treats a type with no underscore as its own provider name' do
      expect(described_class.provider_name_for('porkbun')).to eq('porkbun')
    end

    it 'accepts symbols' do
      expect(described_class.provider_name_for(:cloudflare_record)).to eq('cloudflare')
    end
  end

  describe '.source_for' do
    it 'returns the canonical non-hashicorp sources' do
      expect(described_class.source_for('github')).to eq('integrations/github')
      expect(described_class.source_for('cloudflare')).to eq('cloudflare/cloudflare')
      expect(described_class.source_for('hcloud')).to eq('hetznercloud/hcloud')
      expect(described_class.source_for('akeyless')).to eq('akeyless-community/akeyless')
      expect(described_class.source_for('porkbun')).to eq('marcfrederick/porkbun')
    end

    it 'uses the Terraform Registry casing for datadog (resolving the prior Ruby/Rust drift)' do
      expect(described_class.source_for('datadog')).to eq('DataDog/datadog')
    end

    it 'maps both gcp and google to hashicorp/google' do
      expect(described_class.source_for('gcp')).to eq('hashicorp/google')
      expect(described_class.source_for('google')).to eq('hashicorp/google')
    end

    it 'falls back to hashicorp/<name> for unknown providers (tofu implicit default)' do
      expect(described_class.source_for('random')).to eq('hashicorp/random')
      expect(described_class.source_for('mysteryprovider')).to eq('hashicorp/mysteryprovider')
    end
  end

  describe '.required_providers_for' do
    it 'derives the required_providers hash from resource types, deduped per provider' do
      types = %w[github_repository github_team github_issue_label aws_vpc]
      expect(described_class.required_providers_for(types)).to eq(
        'github' => { source: 'integrations/github' },
        'aws'    => { source: 'hashicorp/aws' }
      )
    end

    it 'is source-only (no version) so tofu resolves the same versions it inferred' do
      rp = described_class.required_providers_for(%w[cloudflare_record])
      expect(rp['cloudflare']).to eq(source: 'cloudflare/cloudflare')
      expect(rp['cloudflare']).not_to have_key(:version)
    end

    it 'returns an empty hash when there are no resources (vacuously magma-clean)' do
      expect(described_class.required_providers_for([])).to eq({})
    end

    # The load-bearing invariant: this is exactly what magma's preflight law A3
    # checks — every resource-type prefix must be a required_providers key.
    it 'satisfies magma law A3: every resource prefix becomes a required_providers key' do
      types = %w[github_repository aws_s3_bucket cloudflare_zone datadog_monitor hcloud_server]
      rp = described_class.required_providers_for(types)
      types.each do |t|
        expect(rp).to have_key(described_class.provider_name_for(t))
      end
    end
  end

  describe '.inject_into_synthesis' do
    it 'adds required_providers for every resource/data provider used' do
      synthesis = { 'resource' => { 'github_repository' => { 'r' => {} }, 'aws_vpc' => { 'v' => {} } } }
      described_class.inject_into_synthesis(synthesis)
      expect(synthesis.dig('terraform', 'required_providers')).to eq(
        'github' => { source: 'integrations/github' },
        'aws'    => { source: 'hashicorp/aws' }
      )
    end

    it 'preserves hand-declared entries (explicit source/version win)' do
      synthesis = {
        'resource'  => { 'github_repository' => {} },
        'terraform' => { 'required_providers' => { 'github' => { source: 'integrations/github', version: '~> 6.0' } } }
      }
      described_class.inject_into_synthesis(synthesis)
      expect(synthesis.dig('terraform', 'required_providers', 'github'))
        .to eq(source: 'integrations/github', version: '~> 6.0')
    end

    it 'leaves a resourceless manifest untouched (vacuously magma-clean)' do
      synthesis = { 'output' => { 'x' => { 'value' => 1 } } }
      described_class.inject_into_synthesis(synthesis)
      expect(synthesis).not_to have_key('terraform')
    end

    it 'derives from data blocks too and returns the same hash object' do
      synthesis = { 'data' => { 'github_repository' => { 'd' => {} } } }
      expect(described_class.inject_into_synthesis(synthesis)).to equal(synthesis)
      expect(synthesis.dig('terraform', 'required_providers', 'github')).to eq(source: 'integrations/github')
    end
  end
end
