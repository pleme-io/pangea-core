# frozen_string_literal: true

require 'json'
require 'open3'

module Pangea
  # Backend selection + auto-discovery layer.
  #
  # Per theory/MAGMA.md §II.11, Pangea supports two execution backends —
  # tofu (historical default) and magma (pleme-io's Rust-native
  # executor). The selected backend consumes Pangea-rendered Terraform
  # JSON and drives plan/apply/destroy.
  #
  # Resolution priority:
  #   1. --backend CLI flag
  #   2. PANGEA_BACKEND env var
  #   3. pangea.yml `backend:` field
  #   4. default: tofu
  #
  # Auto-discovery: each backend's binary is probed via `<bin>
  # capabilities` (magma) / `<bin> version -json` (tofu) on first use;
  # the resulting capabilities manifest gates feature use with typed
  # BackendIncompatible errors.
  module Backend
    # Raised when a workspace requires a feature the selected backend
    # doesn't support.
    class BackendIncompatible < StandardError
      attr_reader :backend, :feature, :alternatives, :hint

      def initialize(backend:, feature:, alternatives: [], hint: nil)
        @backend = backend
        @feature = feature
        @alternatives = alternatives
        @hint = hint
        msg = +"backend=#{backend} does not support #{feature}.\n"
        unless alternatives.empty?
          msg << "  Alternatives: #{alternatives.map { |a| "backend=#{a}" }.join(', ')}\n"
        end
        msg << "  Hint: #{hint}\n" if hint
        super(msg)
      end
    end

    # Raised when no backend binary is reachable on PATH.
    class BackendUnavailable < StandardError; end

    # Normalized capabilities — what every backend impl returns from
    # `.capabilities`. Comparable across tofu / magma so workspace-side
    # code interacts with one shape.
    Capabilities = Struct.new(
      :name,                # 'tofu' | 'magma'
      :version,             # semver string
      :supported_protocols, # ['tfplugin5', 'tfplugin6']
      :input_formats,       # ['hcl2', 'terraform-json'] or ['pangea-ruby-inprocess', 'terraform-json']
      :subcommands,         # array of supported CLI subcommands
      :supports_in_memory_pipeline, # bool — magma true, tofu false
      :supports_workspace_chains,   # bool — magma true, tofu false
      :raw,                 # the full JSON manifest as a Hash
      keyword_init: true,
    )

    # Resolve backend choice from explicit > env > config > default.
    #
    # @param explicit [String, nil]  the --backend flag value
    # @param yml_config [Hash, nil]  the parsed pangea.yml
    # @return [String] one of 'tofu' or 'magma'
    def self.resolve(explicit: nil, yml_config: nil)
      value = explicit ||
              ENV['PANGEA_BACKEND'] ||
              yml_config&.dig('backend') ||
              yml_config&.dig(:backend) ||
              'tofu'
      value = value.to_s
      unless %w[tofu magma].include?(value)
        raise ArgumentError,
              "unknown backend #{value.inspect}; expected 'tofu' or 'magma'"
      end
      value
    end

    # Probe a backend's capabilities by spawning `<bin> capabilities`
    # (magma) or `<bin> version -json` (tofu). Cached per-process.
    #
    # @param name [String] 'tofu' or 'magma'
    # @return [Capabilities]
    # @raise [BackendUnavailable] if the binary isn't on PATH
    def self.capabilities(name)
      @capabilities ||= {}
      @capabilities[name] ||= probe(name)
    end

    def self.probe(name)
      case name
      when 'magma'  then probe_magma
      when 'tofu'   then probe_tofu
      else
        raise ArgumentError, "unknown backend: #{name}"
      end
    end

    def self.probe_magma
      out, status = Open3.capture2('magma', 'capabilities')
      raise BackendUnavailable, "magma binary not on PATH" unless status.success?

      m = JSON.parse(out)
      Capabilities.new(
        name:                          m['tool'],
        version:                       m['version'],
        supported_protocols:           Array(m['supported_protocols']),
        input_formats:                 Array(m['input_formats']),
        subcommands:                   Array(m['subcommands']),
        supports_in_memory_pipeline:   m['in_memory_pipeline_supported'] == true,
        supports_workspace_chains:     m['workspace_chain_supported'] == true,
        raw:                           m,
      )
    rescue Errno::ENOENT
      raise BackendUnavailable, "magma binary not on PATH"
    end

    def self.probe_tofu
      out, status = Open3.capture2('tofu', 'version', '-json')
      raise BackendUnavailable, "tofu binary not on PATH" unless status.success?

      m = JSON.parse(out)
      # tofu's version -json is minimal; we synthesize a Capabilities by
      # composing version + a compile-time table of "tofu has X
      # subcommand" plus capability-flags fixed to tofu's known shape.
      Capabilities.new(
        name:                          'tofu',
        version:                       m['terraform_version'] || m['version'] || 'unknown',
        supported_protocols:           %w[tfplugin5 tfplugin6],
        input_formats:                 %w[hcl2 terraform-json],
        subcommands:                   %w[init plan apply destroy state import workspace
                                          output show refresh taint force-unlock get
                                          fmt validate console],
        supports_in_memory_pipeline:   false,
        supports_workspace_chains:     false,
        raw:                           m,
      )
    rescue Errno::ENOENT
      raise BackendUnavailable, "tofu binary not on PATH"
    end

    # Verify a workspace's requirements against the selected backend.
    # Raises BackendIncompatible with hints when something doesn't match.
    #
    # @param backend [String] 'tofu' or 'magma'
    # @param requires [Hash] e.g. { input_format: 'pangea-ruby-inprocess',
    #                               feature: :in_memory_pipeline }
    def self.verify_compatible!(backend, requires)
      caps = capabilities(backend)
      if (fmt = requires[:input_format])
        unless caps.input_formats.include?(fmt.to_s)
          raise BackendIncompatible.new(
            backend:      backend,
            feature:      "input format '#{fmt}'",
            alternatives: %w[tofu magma].reject { |b| b == backend },
            hint:         "Set `backend: magma` in pangea.yml if you need #{fmt}.",
          )
        end
      end
      if requires[:feature] == :in_memory_pipeline && !caps.supports_in_memory_pipeline
        raise BackendIncompatible.new(
          backend:      backend,
          feature:      'in-memory workspace chains',
          alternatives: ['magma'],
          hint:         "Switch to backend=magma to use §II.9 in-memory chains.",
        )
      end
    end
  end
end
