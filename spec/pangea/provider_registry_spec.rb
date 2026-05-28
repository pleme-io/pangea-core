# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Pangea::ProviderRegistry do
  describe '.provider_name_for' do
    it 'returns the symbol before the first underscore' do
      expect(described_class.provider_name_for('github_repository')).to eq(:github)
      expect(described_class.provider_name_for(:github_branch_protection)).to eq(:github)
      expect(described_class.provider_name_for('aws_s3_bucket')).to eq(:aws)
    end

    it 'returns the whole type as a symbol when there is no underscore' do
      expect(described_class.provider_name_for('porkbun')).to eq(:porkbun)
    end
  end

  describe '.source_for' do
    it 'returns the canonical non-hashicorp Registry sources' do
      expect(described_class.source_for(:github)).to eq('integrations/github')
      expect(described_class.source_for(:cloudflare)).to eq('cloudflare/cloudflare')
      expect(described_class.source_for(:hcloud)).to eq('hetznercloud/hcloud')
      expect(described_class.source_for(:akeyless)).to eq('akeyless-community/akeyless')
      expect(described_class.source_for(:porkbun)).to eq('marcfrederick/porkbun')
    end

    it 'resolves the prior Ruby/Rust drift to the Terraform Registry casing' do
      expect(described_class.source_for(:datadog)).to eq('DataDog/datadog')
    end

    it 'maps both :gcp and :google to hashicorp/google' do
      expect(described_class.source_for(:gcp)).to eq('hashicorp/google')
      expect(described_class.source_for(:google)).to eq('hashicorp/google')
    end

    it 'falls back to hashicorp/<name> for unknown providers (tofu implicit default)' do
      expect(described_class.source_for(:random)).to eq('hashicorp/random')
      expect(described_class.source_for(:mysteryprovider)).to eq('hashicorp/mysteryprovider')
    end

    it 'accepts string or symbol input on the lookup APIs' do
      expect(described_class.source_for('github')).to eq('integrations/github')
      expect(described_class.source_for(:github)).to eq('integrations/github')
    end
  end

  describe '.required_providers_for' do
    it 'derives a symbol-keyed required_providers hash from resource types' do
      types = %i[github_repository github_team github_issue_label aws_vpc]
      expect(described_class.required_providers_for(types)).to eq(
        github: { source: 'integrations/github' },
        aws:    { source: 'hashicorp/aws' }
      )
    end

    it 'is source-only (no version) so tofu resolves the same versions it inferred' do
      rp = described_class.required_providers_for(%i[cloudflare_record])
      expect(rp[:cloudflare]).to eq(source: 'cloudflare/cloudflare')
      expect(rp[:cloudflare]).not_to have_key(:version)
    end

    it 'returns an empty hash when there are no resources (vacuously magma-clean)' do
      expect(described_class.required_providers_for([])).to eq({})
    end

    # The load-bearing invariant: exactly what magma preflight law A3 checks.
    it 'satisfies magma law A3: every resource prefix becomes a required_providers key' do
      types = %i[github_repository aws_s3_bucket cloudflare_zone datadog_monitor hcloud_server]
      rp = described_class.required_providers_for(types)
      types.each do |t|
        expect(rp).to have_key(described_class.provider_name_for(t))
      end
    end
  end

  describe '.inject_into_synthesis' do
    # PRODUCTION shape: TerraformSynthesizer's manifest uses SYMBOL keys
    # throughout (manifest[:resource], manifest[:terraform], …). The finalize
    # honors that natively — no defensive dual-key cruft.
    it 'finalizes a symbol-keyed synthesizer manifest' do
      synthesis = { resource: { github_repository: { 'r' => {} }, aws_vpc: { 'v' => {} } } }
      described_class.inject_into_synthesis(synthesis)
      expect(synthesis.dig(:terraform, :required_providers)).to eq(
        github: { source: 'integrations/github' },
        aws:    { source: 'hashicorp/aws' }
      )
    end

    it 'preserves hand-declared entries — explicit source/version always win' do
      synthesis = {
        resource:  { github_repository: {} },
        terraform: { required_providers: { github: { source: 'integrations/github', version: '~> 6.0' } } }
      }
      described_class.inject_into_synthesis(synthesis)
      expect(synthesis.dig(:terraform, :required_providers, :github))
        .to eq(source: 'integrations/github', version: '~> 6.0')
    end

    it 'leaves a resourceless manifest untouched (vacuously magma-clean)' do
      synthesis = { output: { x: { value: 1 } } }
      described_class.inject_into_synthesis(synthesis)
      expect(synthesis).not_to have_key(:terraform)
    end

    it 'derives from :data blocks too and returns the same hash object' do
      synthesis = { data: { github_repository: { d: {} } } }
      expect(described_class.inject_into_synthesis(synthesis)).to equal(synthesis)
      expect(synthesis.dig(:terraform, :required_providers, :github)).to eq(source: 'integrations/github')
    end
  end
end
