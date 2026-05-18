# frozen_string_literal: true

require 'json'
require 'open3'
require_relative 'backend'

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
        out, err, status = Open3.capture3(binary, 'fixture', 'verify', path.to_s)
        unless status.success?
          raise VerificationFailed,
                "magma fixture verify #{path} failed (exit #{status.exitstatus}):\n#{err}\n#{out}"
        end
        JSON.parse(out)
      end

      # Verify every `.tf.json` under `dir`. Returns the parsed
      # AggregateReport Hash with passed/failed counts + per-workspace
      # breakdown.
      def verify_directory(dir)
        out, _err, status = Open3.capture3(binary, 'fixture', 'verify-dir', dir.to_s)
        # exit==0 means all passed; exit==1 means some failed but JSON
        # is still emitted on stdout; both shapes parseable.
        json = JSON.parse(out)
        unless [0, 1].include?(status.exitstatus)
          raise VerificationFailed,
                "magma fixture verify-dir #{dir} crashed (exit #{status.exitstatus})"
        end
        json
      end

      # Drive `magma flow run <flow.json>` and parse the AggregateReport.
      # `flow` is the typed flow shape (workspaces + edges); see
      # `magma-cli` `FlowFile` / theory/PANGEA-MAGMA-ORCHESTRATION.md §IV.
      def flow(flow_hash)
        require 'tempfile'
        tmp = Tempfile.new(['magma-flow', '.json'])
        begin
          tmp.write(JSON.pretty_generate(flow_hash))
          tmp.close
          out, err, status = Open3.capture3(binary, 'flow', tmp.path)
          unless status.success?
            raise VerificationFailed,
                  "magma flow #{tmp.path} failed (exit #{status.exitstatus}):\n#{err}\n#{out}"
          end
          JSON.parse(out)
        ensure
          tmp.unlink
        end
      end

      # Drive `magma migrate <plan.json>` and parse the MigrationReceipt.
      # `plan` is the typed magma_migrate::MigrationPlan shape.
      def migrate(plan_hash)
        require 'tempfile'
        tmp = Tempfile.new(['magma-migrate', '.json'])
        begin
          tmp.write(JSON.pretty_generate(plan_hash))
          tmp.close
          out, err, status = Open3.capture3(binary, 'migrate', tmp.path)
          unless status.success?
            raise VerificationFailed,
                  "magma migrate #{tmp.path} failed (exit #{status.exitstatus}):\n#{err}\n#{out}"
          end
          JSON.parse(out)
        ensure
          tmp.unlink
        end
      end

      # Drive `magma split` directly. `args` keys:
      # `:from, :from_state, :to, :to_state, :resources (Array<String>), :dry_run (bool)`.
      def split(args)
        argv = [binary, 'split',
                '--from',       args.fetch(:from).to_s,
                '--from-state', args.fetch(:from_state).to_s,
                '--to',         args.fetch(:to).to_s,
                '--to-state',   args.fetch(:to_state).to_s]
        Array(args.fetch(:resources, [])).each { |r| argv += ['--resource', r] }
        argv << '--dry-run' if args[:dry_run]
        out, err, status = Open3.capture3(*argv)
        unless status.success?
          raise VerificationFailed,
                "magma split failed (exit #{status.exitstatus}):\n#{err}\n#{out}"
        end
        JSON.parse(out)
      end

      # Drive `magma merge` directly. `args` keys:
      # `:from, :from_state, :to, :to_state, :dry_run (bool)`.
      def merge(args)
        argv = [binary, 'merge',
                '--from',       args.fetch(:from).to_s,
                '--from-state', args.fetch(:from_state).to_s,
                '--to',         args.fetch(:to).to_s,
                '--to-state',   args.fetch(:to_state).to_s]
        argv << '--dry-run' if args[:dry_run]
        out, err, status = Open3.capture3(*argv)
        unless status.success?
          raise VerificationFailed,
                "magma merge failed (exit #{status.exitstatus}):\n#{err}\n#{out}"
        end
        JSON.parse(out)
      end

      # Reset memoization — for tests that mutate MAGMA_BINARY env.
      def reset!
        @installed = nil
        @binary = nil
        @capabilities = nil
      end

      private

      def probe_capabilities
        out, _err, status = Open3.capture3(binary, 'capabilities')
        unless status.success?
          raise Pangea::Backend::BackendUnavailable,
                "magma capabilities failed (exit #{status.exitstatus})"
        end
        JSON.parse(out)
      rescue Errno::ENOENT
        raise Pangea::Backend::BackendUnavailable, "magma binary not on PATH"
      end
    end

    # Raised when `magma fixture verify` / `verify-dir` reports a
    # non-recoverable failure (subprocess crashed, JSON malformed, etc.).
    # `WorkspaceReport.compatibility.plans_cleanly = false` does NOT
    # raise — it's a typed status surfaced via the matcher.
    class VerificationFailed < StandardError; end
  end
end
