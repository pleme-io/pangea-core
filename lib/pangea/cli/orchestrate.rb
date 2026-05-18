# frozen_string_literal: true

require 'json'

module Pangea
  class CLI
    # `pangea orchestrate <distribution.rb>` — the cross-workspace
    # operator surface (M0.5). Per
    # theory/PANGEA-MAGMA-ORCHESTRATION.md §III.6.
    #
    # The given Ruby file must define exactly one of:
    #
    #   * `orchestrator` — a Pangea::Magma::Orchestrator instance
    #   * `chain`        — a Pangea::Magma::Chain instance
    #   * `distribution` — a Pangea::Magma::Distribution instance
    #
    # `pangea orchestrate` then drives `magma flow run` over the
    # resulting chain and prints the parsed AggregateReport JSON.
    #
    # CLI flags:
    #   --backend <magma|tofu>  Backend to dispatch through (default: magma)
    #   --only foo,bar          Only reconcile these workspaces
    #   --dry-run               Validate + render flow.json; do not run
    module Orchestrate
      class << self
        def run(template_file, backend: nil, only: nil, dry_run: false)
          backend ||= 'magma'
          orch_or_chain = load_template(template_file)

          chain = case orch_or_chain
                  when Pangea::Magma::Orchestrator
                    distribution = orch_or_chain.distribution
                    distribution.to_chain
                  when Pangea::Magma::Chain
                    orch_or_chain
                  when Pangea::Magma::Distribution
                    orch_or_chain.to_chain
                  else
                    raise ArgumentError,
                          "#{template_file} did not define `orchestrator`, " \
                          "`chain`, or `distribution` at top level; got " \
                          "#{orch_or_chain.class}"
                  end

          chain = subset_chain(chain, only) if only && !only.empty?

          if dry_run
            puts JSON.pretty_generate(
              backend: backend,
              chain:   chain.to_h,
              note:    'dry-run: nothing executed; pass without --dry-run to drive backend',
            )
            return
          end

          unless backend == 'magma'
            raise NotImplementedError,
                  "pangea orchestrate currently dispatches through magma only " \
                  "(got --backend=#{backend}); tofu backend lands once tofu " \
                  "exposes a workspace-chain primitive (planned M0.5.x)"
          end

          report = chain.reconcile_all
          puts JSON.pretty_generate(report)
        end

        private

        # Eval the Ruby template file and return the orchestrator /
        # chain / distribution it left in the top-level binding's
        # locals. The orchestrate path deliberately does not pull in
        # the rest of pangea-core (synthesizer/operations/etc.) — only
        # the typed Magma surface, so consumers can drive `pangea
        # orchestrate` without a Pangea Ruby renderer install.
        def load_template(template_file)
          unless File.exist?(template_file)
            raise ArgumentError, "template file not found: #{template_file}"
          end

          # Eval under a fresh top-level binding so `orchestrator = ...`
          # / `chain = ...` / `distribution = ...` become local vars.
          binding_obj = TOPLEVEL_BINDING.dup
          binding_obj.eval(File.read(template_file), template_file)
          %i[orchestrator chain distribution].each do |sym|
            return binding_obj.local_variable_get(sym) if
              binding_obj.local_variables.include?(sym)
          end

          raise ArgumentError,
                "#{template_file}: no orchestrator/chain/distribution found"
        end

        def subset_chain(chain, names)
          wanted = names.map(&:to_sym).to_set
          sub_workspaces = chain.workspaces.select { |k, _| wanted.include?(k) }
          sub_edges      = chain.edges.select { |e| wanted.include?(e.from) && wanted.include?(e.to) }
          Pangea::Magma::Chain.new(
            workspaces:         sub_workspaces,
            edges:              sub_edges,
            output_propagation: chain.output_propagation,
          )
        end
      end
    end
  end
end

require 'set'
require 'pangea/magma'
require 'pangea/magma/chain'
require 'pangea/magma/distribution'
require 'pangea/magma/orchestrator'
