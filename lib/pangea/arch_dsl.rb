# frozen_string_literal: true

# Pangea::ArchDsl — the canonical DSL entry point for every Pangea architecture.
#
# The Pangea TerraformSynthesizer uses a method_missing DSL where several
# common invocations silently misbehave:
#
#   synth.terraform do ... end
#     → block runs with self = outer object, NOT synth. `required_providers`
#       looks up on the calling architecture module and raises NoMethodError.
#
#   synth.provider :name, {hash}
#     → two positional args triggers TooManyFieldValuesError; only block
#       form is valid.
#
#   synth.resource :type, :name, {hash}
#     → same class of failure; must be `resource :type, :name do ... end`
#       with block setters.
#
#   Pangea::RemoteState.output(state_key: 'pangea/platform-vpc')
#     → default convention is `pangea/{template}/{tr}/terraform.tfstate`;
#       explicit overrides hit 404 on the actual bucket layout.
#
# This mixin centralizes the correct patterns behind a strongly-typed
# surface. Architectures include `Pangea::ArchDsl` and call the wrappers
# below instead of raw synth methods.
#
# The bugs this mixin prevents were all encountered during the first
# platform-eks plan; see STANDARDS.md (pleme-io org root) for the
# complete rationale.

module Pangea
  module ArchDsl
    # ══════════════════════════════════════════════════════════════════
    # Block-safe DSL evaluation
    # ══════════════════════════════════════════════════════════════════

    # Run `block` with `synth` as `self` so nested DSL calls like
    # `terraform do ... end` resolve the way Pangea templates expect.
    # Closure-over-args is captured explicitly by the caller (pass them
    # into the block) — inside the block, `self` is the synthesizer.
    #
    # @param synth [TerraformSynthesizer]
    # @yield evaluated with self = synth
    def self.synth_eval(synth, &block)
      raise ArgumentError, 'block required' unless block
      synth.instance_eval(&block)
    end

    # ══════════════════════════════════════════════════════════════════
    # Typed data source registration
    # ══════════════════════════════════════════════════════════════════

    # Register a terraform data source via the synth.data DSL. Uses the
    # block form with explicit setters so every attr is typed by Pangea's
    # schema validation path (when the provider gem registers it) or the
    # raw synth.data path (hand-typed hash) when it does not.
    #
    # @param synth    [TerraformSynthesizer]
    # @param type     [Symbol] terraform data source type (e.g. :aws_network_interface)
    # @param name     [Symbol, String] local name
    # @param attrs    [Hash] attribute hash (string values)
    def self.register_data(synth, type:, name:, attrs:)
      validate_identifier!(name)
      captured_attrs = attrs
      synth.instance_eval do
        data type do
          public_send(name) do
            captured_attrs.each { |k, v| public_send(k, v) }
          end
        end
      end
    end

    # ══════════════════════════════════════════════════════════════════
    # Raw resource registration (for providers without typed gems yet)
    # ══════════════════════════════════════════════════════════════════

    # Register a terraform resource where we don't have a typed Pangea
    # provider-gem method. Takes explicit meta-arg kwargs so those are
    # never silently dropped.
    #
    # @param synth      [TerraformSynthesizer]
    # @param type       [Symbol] terraform resource type (e.g. :aws_vpc_endpoint)
    # @param name       [Symbol, String] local name (canonical underscore form)
    # @param attrs      [Hash] declared resource attributes
    # @option meta      :provider    [Symbol, String] provider alias reference
    # @option meta      :lifecycle   [Hash] lifecycle block
    # @option meta      :depends_on  [Array<String>] explicit dependencies
    # @option meta      :count       [Integer, String] count meta-arg
    # @option meta      :for_each    [String] for_each meta-arg
    def self.register_raw_resource(synth, type:, name:, attrs:, **meta)
      validate_identifier!(name)
      captured_attrs = attrs
      captured_meta  = meta
      synth.instance_eval do
        resource type, name do
          captured_attrs.each { |k, v| public_send(k, v) }
          captured_meta.each { |k, v| public_send(k, v) }
        end
      end
    end

    # ══════════════════════════════════════════════════════════════════
    # RemoteState (defaults the state_key — prevents the 404 class)
    # ══════════════════════════════════════════════════════════════════

    # Fetch a cross-template output. **Never accepts a state_key override.**
    # Default convention (pangea/{template}/{tr}/terraform.tfstate) matches
    # the pangea S3 backend layout exactly; explicit overrides 404.
    #
    # @param template [String] upstream template name (e.g. 'platform-vpc')
    # @param output   [Symbol, String] output key (e.g. :vpc_id)
    # @return [String, Array, nil]
    def self.remote_state_output(template:, output:)
      Pangea::RemoteState.output(template: template, output: output)
    end

    # ══════════════════════════════════════════════════════════════════
    # Canonical identifier (resource name)
    # ══════════════════════════════════════════════════════════════════

    # Canonical resource identifier: underscore-separated, lowercase,
    # optional suffix. Used for every tf address so downstream references
    # never drift between hyphen and underscore forms.
    #
    # @example
    #   Pangea::ArchDsl.managed_id('alpha', suffix: 'system_ng')
    #     # => :alpha_system_ng
    def self.managed_id(base, suffix: nil)
      raise ArgumentError, ':base must not be empty' if base.nil? || base.to_s.empty?
      id = base.to_s.downcase.tr('-', '_')
      id = "#{id}_#{suffix.to_s.downcase.tr('-', '_')}" if suffix
      id.to_sym
    end

    # ══════════════════════════════════════════════════════════════════
    # Set-safe output ref
    # ══════════════════════════════════════════════════════════════════

    # Emit `${tolist(aws_X.N.set_attr)[0].element_attr}` for set-returning
    # terraform attributes. Works around the newer AWS provider where
    # fields like `certificate_authority` and `identity` are sets
    # (unindexable) rather than ordered lists.
    #
    # @example
    #   ref_set_first(:aws_eks_cluster, :alpha, :certificate_authority, :data)
    #     # => "${tolist(aws_eks_cluster.alpha.certificate_authority)[0].data}"
    def self.ref_set_first(resource_type, resource_name, set_attr, element_attr)
      "${tolist(#{resource_type}.#{resource_name}.#{set_attr})[0].#{element_attr}}"
    end

    # ══════════════════════════════════════════════════════════════════
    # Helpers
    # ══════════════════════════════════════════════════════════════════

    IDENTIFIER_PATTERN = /\A[a-z0-9_]+\z/

    def self.validate_identifier!(name)
      s = name.to_s
      return if s.match?(IDENTIFIER_PATTERN)
      raise ArgumentError,
            "identifier '#{s}' must be lowercase snake_case (matching #{IDENTIFIER_PATTERN.source}); " \
            'use Pangea::ArchDsl.managed_id to canonicalize'
    end
  end
end
