# frozen_string_literal: true

require 'json'
require_relative 'runner'

module Pangea
  module Magma
    # Typed state-organization migration — the load-bearing surgical
    # operation per theory/PANGEA-MAGMA-ORCHESTRATION.md §III.3 + §V.
    #
    # Migrations move resources from one workspace's state to another
    # without recreate, preserving identity (ARNs, UUIDs, etc.).
    #
    # Authors:
    #
    #   migration = Pangea::Magma::Migration.declare(
    #     from: :k3s_permissions,
    #     to:   :platform_iam,
    #     resources: [
    #       { kind: :managed,
    #         address:     'aws_iam_role.k3s_node',
    #         new_address: 'aws_iam_role.platform_k3s_node' },
    #     ],
    #     preserve: [:resource_identity, :tags, :dependent_resources],
    #     dry_run: true,
    #   )
    #
    #   plan = migration.plan
    #   plan.summary    # human-readable summary
    #   plan.apply!     # → `magma migrate <plan.json>`
    #
    # The Rust-side `magma_migrate::Migration` + `magma migrate`
    # subcommand land in M0.2; this Ruby-side declaration ships now
    # against the typed plan-emission interface.
    class Migration
      ResourceMove = Struct.new(:kind, :address, :new_address,
                                :new_address_pattern, :identity,
                                keyword_init: true) do
        def to_h
          { kind: kind.to_s, address: address, new_address: new_address,
            new_address_pattern: new_address_pattern,
            identity: identity }.compact
        end
      end

      # Typed migration plan — returned by Migration#plan; consumed by
      # `magma migrate` subprocess + dry-run inspection.
      class Plan
        attr_reader :migration, :actions, :would_recreate, :warnings

        def initialize(migration:, actions:, would_recreate: [], warnings: [])
          @migration      = migration
          @actions        = actions
          @would_recreate = would_recreate
          @warnings       = warnings
        end

        def invariants_satisfied?
          @would_recreate.empty?
        end

        def summary
          lines = []
          lines << "Migration: #{@migration.from} → #{@migration.to}"
          lines << "  #{@actions.size} action(s)"
          lines << "  recreates: #{@would_recreate.size}" if @would_recreate.any?
          lines << "  warnings: #{@warnings.size}" if @warnings.any?
          lines.join("\n")
        end

        # Apply the typed Plan via `magma migrate <plan.json>`. Returns
        # the parsed `MigrationReceipt` Hash on success (with BLAKE3
        # state-file hashes pre/post per
        # theory/PANGEA-MAGMA-ORCHESTRATION.md §V). Raises on either
        # invariant violation or magma exit≠0.
        def apply!
          raise InvariantViolation,
                "would recreate: #{@would_recreate.inspect}" unless invariants_satisfied?

          unless @migration.from_state_path
            raise ArgumentError,
                  "Migration#apply! requires from_state_path — declare with " \
                  "`from_state_path: 'workspaces/<src>/terraform.tfstate'` " \
                  "(see theory/PANGEA-MAGMA-ORCHESTRATION.md §V)"
          end
          unless @migration.to_state_path
            raise ArgumentError,
                  "Migration#apply! requires to_state_path — declare with " \
                  "`to_state_path: 'workspaces/<dst>/terraform.tfstate'`"
          end

          # Render typed MigrationPlan JSON that `magma migrate` consumes
          # directly (the on-disk shape of magma_migrate::MigrationPlan)
          # and dispatch through the shared Runner. The Runner owns
          # tempfile cleanup + error capture.
          Runner.invoke('migrate', json_arg: {
            from: { name: @migration.from.to_s, state_path: @migration.from_state_path },
            to:   { name: @migration.to.to_s,   state_path: @migration.to_state_path   },
            moves: @actions.map { |a| { source_address: a.address, target_address: a.new_address } },
            preserve: {
              resource_identity:    @migration.preserve.include?(:resource_identity),
              tags:                 @migration.preserve.include?(:tags),
              dependent_resources:  @migration.preserve.include?(:dependent_resources),
            },
            dry_run: @migration.dry_run,
          })
        end

        def to_h
          {
            migration: @migration.to_h,
            actions:   @actions.map(&:to_h),
            would_recreate: @would_recreate,
            warnings:  @warnings,
          }
        end

        def to_json(*args)
          to_h.to_json(*args)
        end
      end

      # Inherits from Pangea::Magma::Error so `rescue
      # Pangea::Magma::Error` catches every typed magma failure.
      class InvariantViolation < Pangea::Magma::Error; end

      class << self
        def declare(from:, to:, resources:, preserve: [:resource_identity],
                    dry_run: true, from_state_path: nil, to_state_path: nil)
          raise ArgumentError, 'from required' if from.nil?
          raise ArgumentError, 'to required'   if to.nil?
          raise ArgumentError, 'resources required, got empty' if resources.empty?

          moves = resources.map { |r| ResourceMove.new(**r) }
          new(from: from.to_sym, to: to.to_sym,
              resources: moves, preserve: preserve, dry_run: dry_run,
              from_state_path: from_state_path, to_state_path: to_state_path)
        end
      end

      attr_reader :from, :to, :resources, :preserve, :dry_run,
                  :from_state_path, :to_state_path

      def initialize(from:, to:, resources:, preserve:, dry_run:,
                     from_state_path: nil, to_state_path: nil)
        @from            = from
        @to              = to
        @resources       = resources
        @preserve        = preserve
        @dry_run         = dry_run
        @from_state_path = from_state_path
        @to_state_path   = to_state_path
      end

      # Produce a typed Plan. M0.1 stub: emits a 1:1 action per
      # declared ResourceMove + checks for obvious recreate triggers.
      # M0.2 replaces this with a real `magma migrate plan` call.
      def plan
        actions = @resources.map do |r|
          ResourceMove.new(
            kind:        r.kind || :managed,
            address:     r.address,
            new_address: r.new_address || r.address,
            identity:    "<resolved-at-runtime>",
          )
        end
        # Identify any resource whose preserve flags can't be satisfied
        # at the declared level. M0.1 placeholder: empty list.
        would_recreate = []
        warnings = []
        warnings << "address-pattern moves require M0.2 magma migrate to expand" if
          @resources.any? { |r| r.new_address_pattern }

        Plan.new(migration: self, actions: actions,
                 would_recreate: would_recreate, warnings: warnings)
      end

      def to_h
        {
          from:            @from.to_s,
          to:              @to.to_s,
          resources:       @resources.map(&:to_h),
          preserve:        @preserve.map(&:to_s),
          dry_run:         @dry_run,
          from_state_path: @from_state_path,
          to_state_path:   @to_state_path,
        }.compact
      end

      def to_json(*args)
        to_h.to_json(*args)
      end
    end
  end
end
