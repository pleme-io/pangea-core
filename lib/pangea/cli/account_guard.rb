# frozen_string_literal: true

require 'json'
require 'open3'
require 'yaml'

module Pangea
  class CLI
    # Refuses an operation whose ambient AWS identity is in a different account
    # than the workspace declares.
    #
    # ── ★ THE HOLE THIS CLOSES, measured 2026-09-12 ────────────────────────
    #
    # `pangea` deliberately renders NO `provider` block — the resource provider
    # authenticates from the ambient `AWS_PROFILE`, and that is by design (it is
    # what lets the s3 BACKEND authenticate against a different account than the
    # resources, see Config#resolve_backend_config). Measured: zero of the
    # workspaces in pangea-architectures render a provider block.
    #
    # The consequence is that `account:` in a workspace's pangea.yml is
    # DOCUMENTATION. Nothing compares it to the identity the apply will actually
    # use. Run with the wrong profile — or with none, so the default is taken —
    # and the resources are created in that account instead, and the run reports
    # success.
    #
    # That is not hypothetical. `camelot-eks-operator-iam` declares
    # `account: akeyless-development` (376129857990) and its own header says
    # "Applied once, locally, under the human operator's own SSO session
    # (AWS_PROFILE=akeyless-development)". Applied without that variable set, it
    # created an IAM user, four policies, three attachments and a LIVE ACCESS KEY
    # in **akeyless-staging** (980459274626), printed `Apply: 9 added, 0 changed,
    # 0 destroyed`, and wrote a state file saying it had succeeded. The only
    # reason it was caught is that a verification query against the DECLARED
    # account came back `NoSuchEntity` — the apply's own output was green.
    #
    # A wrong-account apply is the expensive kind of wrong: it is invisible in
    # the tool's output, it is real infrastructure someone pays for, and for an
    # IAM workspace it mints a credential in an account that was never meant to
    # hold it.
    #
    # ── What this refuses, and what it deliberately does not ───────────────
    #
    #   declared + resolvable + MATCHES ambient   -> proceed
    #   declared + resolvable + DIFFERS           -> REFUSE, naming both
    #   declared + NOT in the accounts registry   -> REFUSE (a name nothing
    #                                                defines is a typo, and a
    #                                                typo that skipped the check
    #                                                would be the hole again)
    #   NOT declared                              -> SKIP, and say so
    #   ambient identity unreadable               -> REFUSE
    #
    # ★ The last one is the one worth arguing for. "Could not verify" is not
    # "verified" — degrading to allow is exactly how a guard becomes decorative,
    # and every operation this protects needs working AWS credentials anyway, so
    # an unreadable identity is already a broken run.
    #
    # ★ The undeclared case SKIPS rather than refuses, because `account:` is
    # optional today and making it mandatory here would break every workspace
    # that has never declared one. That is a real remaining gap, not a closed
    # one: `pending-pangea-account-mandatory`.
    module AccountGuard
      class AccountMismatch < StandardError; end

      # Result of a check, so callers can report rather than guess.
      Verdict = Struct.new(:state, :declared, :expected_id, :actual_id, :message)

      module_function

      # @param template_dir [String] the workspace directory
      # @param sts [#call] injectable identity reader, for tests. Returns the
      #   12-digit account id as a String, or nil when it cannot be read.
      # @return [Verdict]
      def check(template_dir, sts: method(:ambient_account_id))
        declared = declared_account(template_dir)
        return Verdict.new(:skipped, nil, nil, nil,
                           'no `account:` declared — nothing to compare') if declared.nil?

        expected = account_id_for(declared, template_dir)
        if expected.nil?
          return Verdict.new(:unresolvable, declared, nil, nil,
                             "workspace declares `account: #{declared}` but no such entry exists " \
                             'in the `accounts:` registry of any pangea.yml above it. A name ' \
                             'nothing defines cannot be verified, and skipping the check for it ' \
                             'would reopen the hole the check exists to close.')
        end

        actual = sts.call
        if actual.nil? || actual.to_s.empty?
          return Verdict.new(:unreadable, declared, expected, nil,
                             'could not read the ambient AWS identity (`sts get-caller-identity`). ' \
                             'Refusing: "could not verify" is not "verified", and this operation ' \
                             'needs working credentials regardless.')
        end

        if actual.to_s == expected.to_s
          Verdict.new(:ok, declared, expected, actual.to_s, nil)
        else
          Verdict.new(:mismatch, declared, expected, actual.to_s,
                      "this workspace declares `account: #{declared}` (#{expected}) but the " \
                      "ambient AWS identity is in account #{actual}. pangea renders NO provider " \
                      "block, so the apply would create resources in #{actual} and report " \
                      "success.\n\nSet the profile for the declared account and re-run:\n" \
                      "  AWS_PROFILE=#{declared} pangea <op> <template>")
        end
      end

      # Raises unless the check passes or is legitimately skipped.
      def assert!(template_dir, sts: method(:ambient_account_id))
        v = check(template_dir, sts: sts)
        return v if %i[ok skipped].include?(v.state)

        raise AccountMismatch, v.message
      end

      # The `account:` a workspace declares, or nil.
      def declared_account(template_dir)
        yml = nearest_pangea_yml(template_dir)
        return nil unless yml

        cfg = YAML.safe_load(File.read(yml)) || {}
        a = cfg['account']
        a && !a.to_s.empty? ? a.to_s : nil
      end

      # Resolve an account NAME to its id via the `accounts:` registry, searching
      # the workspace's own pangea.yml first and then upward — the registry is
      # conventionally declared once at the repo root.
      def account_id_for(name, template_dir)
        each_pangea_yml(template_dir) do |yml|
          cfg = YAML.safe_load(File.read(yml)) || {}
          entry = (cfg['accounts'] || {})[name]
          id = entry && entry['account_id']
          return id.to_s if id && !id.to_s.empty?
        end
        nil
      end

      def ambient_account_id
        out, _err, status = Open3.capture3('aws', 'sts', 'get-caller-identity', '--output', 'json')
        return nil unless status.success?

        JSON.parse(out)['Account']
      rescue StandardError
        nil
      end

      def nearest_pangea_yml(dir)
        each_pangea_yml(dir) { |yml| return yml }
        nil
      end

      # Yields every pangea.yml from `dir` upward to the filesystem root.
      def each_pangea_yml(dir)
        d = File.expand_path(dir)
        loop do
          candidate = File.join(d, 'pangea.yml')
          yield candidate if File.exist?(candidate)
          parent = File.dirname(d)
          break if parent == d

          d = parent
        end
      end
    end
  end
end
