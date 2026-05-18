# frozen_string_literal: true

require 'json'
require 'open3'
require_relative 'backend'
require_relative 'magma/runner'

module Pangea
  # Ruby wrapper around the `magma` CLI's fixture / capabilities surface.
  #
  # Per theory/MAGMA.md §II.8 interface 1 (drop-in CLI), §II.11 (backend
  # auto-discovery), and §II.6 (test corpus). This module exists so
  # pangea-* gems' rspec suites can verify "this workspace works under
  # magma" with one matcher invocation — no shelling out manually, no
  # JSON parsing per consumer.
  #
  # # Usage
  #
  #   require 'pangea/magma'
  #
  #   # Direct API:
  #   report = Pangea::Magma.verify_workspace('workspaces/seph-vpc')
  #   report['resource_change_count'] # => 3
  #   report['providers']             # => ["hashicorp/aws"]
  #
  #   # Or rspec matchers (require 'pangea/magma/matchers'):
  #   it 'plans cleanly under magma' do
  #     expect('workspaces/seph-vpc').to plan_cleanly_under_magma
  #   end
  #
  # # Binary resolution
  #
  # `MAGMA_BINARY` env var overrides the binary path. Default is `magma`
  # (PATH lookup). When magma isn't installed, `installed?` returns
  # false and rspec matchers skip-with-print rather than failing hard
  # so CI on machines without magma doesn't break.
  module Magma
    class << self
      # Path to the magma binary. Override via `MAGMA_BINARY` env var.
      def binary
        @binary ||= ENV['MAGMA_BINARY'] || 'magma'
      end

      attr_writer :binary

      # True if the magma binary is reachable + responsive.
      def installed?
        return @installed unless @installed.nil?
        _out, _err, status = Open3.capture3(binary, '--version')
        @installed = status.success?
      rescue Errno::ENOENT
        @installed = false
      end

      # Probe magma's capability manifest. Returns the parsed JSON
      # Hash (matching the schema in theory/MAGMA.md §II.11) or
      # raises Pangea::Backend::BackendUnavailable if magma isn't on PATH.
      def capabilities
        @capabilities ||= probe_capabilities
      end

      # Verify a single workspace (directory or single `.tf.json` file).
      # Returns the parsed WorkspaceReport Hash; raises VerificationFailed
      # on non-zero exit.
      def verify_workspace(path)
        Runner.invoke('fixture', argv_extras: ['verify', path.to_s])
      rescue Runner::SubprocessError => e
        raise VerificationFailed, e.message
      end

      # Verify every `.tf.json` under `dir`. Returns the parsed
      # AggregateReport Hash with passed/failed counts + per-workspace
      # breakdown. Allow exit=1 since the CLI still emits JSON when
      # some fixtures fail.
      def verify_directory(dir)
        Runner.invoke('fixture', argv_extras: ['verify-dir', dir.to_s],
                      allow_exit: [1])
      rescue Runner::SubprocessError => e
        raise VerificationFailed, e.message
      end

      # Drive `magma flow run <flow.json>` and parse the AggregateReport.
      # `flow` is the typed flow shape (workspaces + edges); see
      # `magma-flow` / theory/PANGEA-MAGMA-ORCHESTRATION.md §IV.
      def flow(flow_hash)
        Runner.invoke('flow', json_arg: flow_hash)
      rescue Runner::SubprocessError => e
        raise VerificationFailed, e.message
      end

      # Drive `magma migrate <plan.json>` and parse the MigrationReceipt.
      # `plan` is the typed magma_migrate::MigrationPlan shape.
      def migrate(plan_hash)
        Runner.invoke('migrate', json_arg: plan_hash)
      rescue Runner::SubprocessError => e
        raise VerificationFailed, e.message
      end

      # Drive `magma split` directly. `args` keys:
      # `:from, :from_state, :to, :to_state, :resources (Array<String>), :dry_run (bool)`.
      def split(args)
        extras = ['--from',       args.fetch(:from).to_s,
                  '--from-state', args.fetch(:from_state).to_s,
                  '--to',         args.fetch(:to).to_s,
                  '--to-state',   args.fetch(:to_state).to_s]
        Array(args.fetch(:resources, [])).each { |r| extras += ['--resource', r] }
        extras << '--dry-run' if args[:dry_run]
        Runner.invoke('split', argv_extras: extras)
      rescue Runner::SubprocessError => e
        raise VerificationFailed, e.message
      end

      # Drive `magma merge` directly. `args` keys:
      # `:from, :from_state, :to, :to_state, :dry_run (bool)`.
      def merge(args)
        extras = ['--from',       args.fetch(:from).to_s,
                  '--from-state', args.fetch(:from_state).to_s,
                  '--to',         args.fetch(:to).to_s,
                  '--to-state',   args.fetch(:to_state).to_s]
        extras << '--dry-run' if args[:dry_run]
        Runner.invoke('merge', argv_extras: extras)
      rescue Runner::SubprocessError => e
        raise VerificationFailed, e.message
      end

      # Reset memoization — for tests that mutate MAGMA_BINARY env.
      def reset!
        @installed = nil
        @binary = nil
        @capabilities = nil
      end

      private

      def probe_capabilities
        Runner.invoke('capabilities')
      rescue Runner::SubprocessError => e
        raise Pangea::Backend::BackendUnavailable,
              "magma capabilities failed (exit #{e.exit_code})"
      rescue Errno::ENOENT
        raise Pangea::Backend::BackendUnavailable, "magma binary not on PATH"
      end
    end

    # Base class for every Pangea::Magma-raised error. Lets callers
    # `rescue Pangea::Magma::Error` for any magma subprocess failure
    # (verify, flow, migrate, split, merge, capabilities, …).
    class Error < StandardError; end

    # Raised when `magma fixture verify` / `verify-dir` reports a
    # non-recoverable failure (subprocess crashed, JSON malformed, etc.).
    # `WorkspaceReport.compatibility.plans_cleanly = false` does NOT
    # raise — it's a typed status surfaced via the matcher.
    class VerificationFailed < Error; end
  end
end
