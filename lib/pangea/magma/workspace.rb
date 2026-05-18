# frozen_string_literal: true

require 'json'

module Pangea
  module Magma
    # Typed Pangea workspace declaration — the M0.1 primitive that
    # mirrors `magma_pangea::workspace::Workspace` (the Rust trait).
    # Per theory/PANGEA-MAGMA-ORCHESTRATION.md §III.1.
    #
    # Authors:
    #
    #   vpc = Pangea::Magma::Workspace.declare(
    #     name:           :seph_vpc,
    #     template:       'seph_vpc.rb',
    #     workspace_dir:  'workspaces/seph-vpc',
    #     inputs: {
    #       cidr_block: { type: String, default: '10.0.0.0/16' },
    #     },
    #     outputs: {
    #       vpc_id:    { type: String, sensitive: false },
    #       subnet_id: { type: String },
    #     },
    #     requires: {
    #       input_format: 'terraform-json',
    #     },
    #   )
    #
    # Then composes into a Chain (see chain.rb) for multi-workspace
    # orchestration. Each Workspace consumes magma-arch-test under the
    # hood via Pangea::Magma.verify_workspace.
    class Workspace
      # Typed slot — input or output declaration.
      Slot = Struct.new(:name, :type, :default, :sensitive, :description,
                        keyword_init: true) do
        def to_h
          { name: name, type: type.to_s,
            default: default, sensitive: sensitive,
            description: description }.compact
        end
      end

      # Typed requirements — checked at orchestration build time via
      # Pangea::Backend.verify_compatible! against the chosen backend.
      Requires = Struct.new(:feature, :input_format, keyword_init: true) do
        def to_h
          { feature: feature, input_format: input_format }.compact
        end

        def empty?
          feature.nil? && input_format.nil?
        end
      end

      # Default requires for every Pangea-rendered workspace. Most
      # workspaces target the terraform-json input format; declaring
      # this on every workspace is boilerplate, so we make it the
      # default and let exotic workspaces override it.
      DEFAULT_REQUIRES = { input_format: 'terraform-json' }.freeze

      class << self
        # Build a typed Workspace declaration. Raises ArgumentError if
        # the declaration is malformed.
        def declare(name:, template:, workspace_dir:,
                    inputs: {}, outputs: {}, requires: DEFAULT_REQUIRES)
          raise ArgumentError, 'name required (Symbol or String)' if name.nil?
          raise ArgumentError, 'template required' if template.nil?
          raise ArgumentError, 'workspace_dir required' if workspace_dir.nil?

          new(
            name:          name.to_sym,
            template:      template.to_s,
            workspace_dir: workspace_dir.to_s,
            inputs:        coerce_slots(inputs),
            outputs:       coerce_slots(outputs),
            requires:      Requires.new(**requires),
          )
        end

        private

        def coerce_slots(decls)
          decls.transform_values do |decl|
            decl = decl.dup
            decl[:type] ||= String
            Slot.new(**decl)
          end
        end
      end

      attr_reader :name, :template, :workspace_dir, :inputs, :outputs, :requires

      def initialize(name:, template:, workspace_dir:,
                     inputs:, outputs:, requires:)
        @name          = name
        @template      = template
        @workspace_dir = workspace_dir
        @inputs        = inputs
        @outputs       = outputs
        @requires      = requires
      end

      # Verify this workspace works under the chosen backend. Routes
      # through Pangea::Magma.verify_workspace + Pangea::Backend.
      def verify(backend: 'magma')
        Pangea::Backend.verify_compatible!(backend, @requires.to_h) unless @requires.empty?
        Pangea::Magma.verify_workspace(@workspace_dir)
      end

      # Serialize for magma flow run consumption.
      def to_h
        {
          name:          @name.to_s,
          template:      @template,
          workspace_dir: @workspace_dir,
          inputs:        @inputs.transform_values(&:to_h),
          outputs:       @outputs.transform_values(&:to_h),
          requires:      @requires.to_h,
        }
      end

      def to_json(*args)
        to_h.to_json(*args)
      end
    end
  end
end
