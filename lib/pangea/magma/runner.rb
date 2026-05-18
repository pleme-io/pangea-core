# frozen_string_literal: true

require 'json'
require 'open3'
require 'tempfile'

# Forward-declare the Error superclass when this file is loaded
# standalone (Pangea::Magma module loaded later auto-inherits).
module Pangea
  module Magma
    unless defined?(Pangea::Magma::Error)
      class Error < StandardError; end
    end
  end
end

module Pangea
  module Magma
    # Shared command-line plumbing for every Ruby↔magma invocation.
    # Replaces hand-rolled Open3.capture3 + Tempfile + JSON.parse blocks
    # that were duplicated across Chain#reconcile_all, Migration#apply!,
    # Pangea::Magma.{flow,migrate,split,merge}.
    #
    # Three call shapes:
    #
    #   Runner.invoke('capabilities')              # → parsed JSON Hash
    #   Runner.invoke('flow', stdin: nil, json_arg: flow_hash)
    #     # writes flow_hash to a tempfile, passes its path as argv,
    #     # cleans up. Returns parsed JSON.
    #   Runner.invoke('split', argv_extras: %w[--from x --from-state y …])
    #     # passes extras verbatim. Returns parsed JSON.
    #
    # Errors raised:
    #   Pangea::Magma::Runner::SubprocessError — non-zero exit with
    #     full stdout/stderr captured for the operator.
    #
    # Why this exists: each ad-hoc capture3 block forgot one thing —
    # tempfile cleanup, JSON parse on failure, stdout vs stderr — and
    # debugging was harder for it. One typed surface here means
    # downstream wrappers cannot regress those concerns.
    class Runner
      # Inherits from Pangea::Magma::Error so callers can `rescue
      # Pangea::Magma::Error` and catch any failure raised by the
      # shared command-line plumbing.
      class SubprocessError < Pangea::Magma::Error
        attr_reader :exit_code, :stdout, :stderr, :command

        def initialize(command:, exit_code:, stdout:, stderr:)
          @command   = command
          @exit_code = exit_code
          @stdout    = stdout
          @stderr    = stderr
          super("#{command.first} (#{command[1..].join(' ')}) failed (exit #{exit_code}):\n" \
                "#{stderr}\n#{stdout}")
        end
      end

      class << self
        # Invoke the magma binary with a subcommand + optional extras
        # and/or JSON-file argument. Returns the parsed JSON Hash on
        # stdout (always — `magma` subcommands emit JSON on stdout
        # for success, JSON or text on stderr for failure).
        #
        # Options:
        #   :argv_extras — Array<String> of additional CLI args
        #   :json_arg    — Hash; rendered to a tempfile, path appended
        #                  to argv. The file is unlinked on return.
        #   :allow_exit  — Array<Integer> of acceptable exit codes
        #                  besides 0; output is still parsed. Used by
        #                  `magma fixture verify-dir` which exits 1
        #                  when fixtures fail but still emits JSON.
        #   :parse       — Symbol: :json (default) or :raw (return out).
        def invoke(subcommand, argv_extras: [], json_arg: nil, allow_exit: [], parse: :json)
          argv = [Pangea::Magma.binary, subcommand, *argv_extras]
          tmp = nil
          if json_arg
            tmp = Tempfile.new(["magma-#{subcommand}", '.json'])
            tmp.write(JSON.pretty_generate(json_arg))
            tmp.close
            argv << tmp.path
          end
          out, err, status = Open3.capture3(*argv)
          allowed = [0, *allow_exit]
          unless allowed.include?(status.exitstatus)
            raise SubprocessError.new(
              command:   argv,
              exit_code: status.exitstatus,
              stdout:    out,
              stderr:    err,
            )
          end
          parse == :raw ? out : JSON.parse(out)
        ensure
          tmp&.unlink
        end
      end
    end
  end
end
