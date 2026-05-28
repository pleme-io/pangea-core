# frozen_string_literal: true

module Pangea
  # Pangea::ProviderRegistry — the canonical map from a Terraform
  # resource-type prefix to its provider's Registry source, and the
  # derivation of `terraform.required_providers` from the set of
  # resource/data types a synthesized workspace actually uses.
  #
  # == Why this exists
  #
  # A Terraform resource type's prefix-before-the-first-underscore is its
  # provider's local name: `github_repository` → `github`, `aws_vpc` → `aws`.
  # OpenTofu *infers* the provider source from that prefix (defaulting to
  # `hashicorp/<name>`) when a workspace omits `terraform.required_providers`,
  # so most Pangea workspaces historically never declared the block.
  #
  # magma's preflight architecture laws refuse that inference:
  #   * Law A2 — a workspace with resources MUST carry a non-empty
  #              `terraform.required_providers`.
  #   * Law A3 — every resource-type prefix MUST be a key in it.
  # (see magma-test-laws/src/architecture.rs; theory/EXECUTOR-MIGRATION.md)
  #
  # So a "magma-clean" config must declare every provider it uses. Rather
  # than ask each architecture/workspace to hand-write the block (fragile,
  # since `synth.terraform do required_providers(...) end` rebinds `self`
  # and raises NoMethodError — see Pangea::ArchDsl), the synthesizer derives
  # the block mechanically from the resources it emitted, using this
  # registry as the single source of truth.
  #
  # == Layer + convention
  #
  # This module is a *synthesizer-side helper*. Its in-memory shape matches
  # `TerraformSynthesizer`'s manifest convention — **symbol keys** for
  # top-level blocks and the provider local name (`:resource`, `:terraform`,
  # `:required_providers`, `:github`, …; see `RESOURCE_KEYS = %i[…]` and
  # `manifest[:terraform]` in terraform-synthesizer.rb). The public lookup
  # APIs (`source_for`, `provider_name_for`) are forgiving on input —
  # strings or symbols — but the structures the registry produces and
  # writes use the synthesizer's native symbol shape.
  #
  # This consolidates two previously-drifted maps:
  #   * pangea-cli  ArchitectureService#provider_source  (Ruby, by provider name)
  #   * magma       magma-apply::default_provider_for     (Rust, by type prefix)
  # which disagreed on datadog casing. The casing here matches the actual
  # Terraform Registry namespaces.
  module ProviderRegistry
    module_function

    # Provider local name → canonical Terraform Registry source.
    #
    # Symbol-keyed (matches the synthesizer's manifest shape). Only
    # non-`hashicorp/<name>` providers + notable hashicorp ones need an
    # entry; unknown prefixes fall back to `hashicorp/<name>` — exactly
    # OpenTofu's own implicit default.
    SOURCES = {
      aws:        'hashicorp/aws',
      azurerm:    'hashicorp/azurerm',
      google:     'hashicorp/google',
      gcp:        'hashicorp/google',
      kubernetes: 'hashicorp/kubernetes',
      helm:       'hashicorp/helm',
      null:       'hashicorp/null',
      random:     'hashicorp/random',
      tls:        'hashicorp/tls',
      local:      'hashicorp/local',
      external:   'hashicorp/external',
      archive:    'hashicorp/archive',
      time:       'hashicorp/time',
      cloudflare: 'cloudflare/cloudflare',
      github:     'integrations/github',
      datadog:    'DataDog/datadog',
      akeyless:   'akeyless-community/akeyless',
      hcloud:     'hetznercloud/hcloud',
      splunk:     'splunk/splunk',
      porkbun:    'marcfrederick/porkbun'
    }.freeze

    # The provider local name (symbol) for a Terraform resource/data type:
    # the segment before the first underscore. `:github_repository` /
    # `'github_repository'` → `:github`. Returns the type itself (as
    # symbol) when there's no underscore.
    def provider_name_for(type)
      t = type.to_s
      idx = t.index('_')
      (idx ? t[0...idx] : t).to_sym
    end

    # Canonical Terraform Registry source for a provider local name,
    # falling back to `hashicorp/<name>` (OpenTofu's implicit default) for
    # any name not in SOURCES. Accepts string or symbol.
    def source_for(name)
      key = name.to_sym
      SOURCES.fetch(key) { "hashicorp/#{key}" }
    end

    # Given an enumerable of Terraform resource/data TYPE names, build the
    # `terraform.required_providers` hash they imply, keyed by provider
    # local name (symbol):
    #
    #   required_providers_for(%i[github_repository github_team aws_vpc])
    #   # => { github: { source: "integrations/github" },
    #   #      aws:    { source: "hashicorp/aws" } }
    #
    # Source-only (no `version`): tofu then resolves the same provider
    # versions it previously inferred, keeping rendered output a
    # byte-compatible superset of today's. Callers merge this UNDER any
    # hand-declared entries so explicit `source`/`version` choices win.
    def required_providers_for(types)
      types.each_with_object({}) do |type, acc|
        name = provider_name_for(type)
        next if name.to_s.empty?

        acc[name] ||= { source: source_for(name) }
      end
    end

    # Finalize a synthesized manifest IN PLACE: ensure it carries a
    # `terraform.required_providers` entry for every provider its
    # `:resource` / `:data` blocks use. Existing (hand-declared) entries
    # are preserved — only missing providers are added — so explicit
    # `source`/`version` choices always win. Returns the (same) hash.
    #
    # This is the render-path finalize step: call it once, after a
    # workspace's DSL body has run, in every render path (the operator's
    # in-pod synth and pangea-cli's ArchitectureService). It makes
    # rendered output satisfy magma laws A2/A3 by construction while
    # leaving tofu's resolution unchanged. A workspace with no resources
    # is left untouched (vacuously magma-clean).
    def inject_into_synthesis(synthesis)
      return synthesis unless synthesis.is_a?(Hash)

      types = %i[resource data].flat_map do |block|
        blk = synthesis[block]
        blk.is_a?(Hash) ? blk.keys.map(&:to_s) : []
      end
      return synthesis if types.empty?

      terraform = (synthesis[:terraform] ||= {})
      existing  = (terraform[:required_providers] ||= {})
      required_providers_for(types).each do |name, spec|
        existing[name] = spec unless existing.key?(name)
      end
      synthesis
    end
  end
end
