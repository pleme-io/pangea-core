# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'
require 'fileutils'
require 'pangea/cli/account_guard'

# The guard that would have refused the 2026-09-12 wrong-account apply.
#
# Every example injects the STS reader, so nothing here talks to AWS.
RSpec.describe Pangea::CLI::AccountGuard do
  def workspace(account:, registry: nil)
    root = Dir.mktmpdir
    if registry
      File.write(File.join(root, 'pangea.yml'), YAML.dump('accounts' => registry))
    end
    ws = File.join(root, 'workspaces', 'thing')
    FileUtils.mkdir_p(ws)
    body = {}
    body['account'] = account if account
    File.write(File.join(ws, 'pangea.yml'), YAML.dump(body))
    ws
  end

  let(:registry) do
    {
      'akeyless-development' => { 'account_id' => '376129857990' },
      'akeyless-staging' => { 'account_id' => '980459274626' },
    }
  end

  describe 'the incident it exists for' do
    # ★ THE EXACT SHAPE OF THE 2026-09-12 MISTAKE. The workspace declared
    # akeyless-development; the ambient profile was the default, which resolved
    # to akeyless-staging; the apply created an IAM user, four policies and a
    # LIVE ACCESS KEY there and printed "9 added, 0 changed, 0 destroyed".
    it 'refuses when the ambient identity is a DIFFERENT account' do
      ws = workspace(account: 'akeyless-development', registry: registry)

      expect {
        described_class.assert!(ws, sts: -> { '980459274626' })
      }.to raise_error(described_class::AccountMismatch, /declares `account: akeyless-development`/)
    end

    it 'names BOTH accounts and the fix, not just that something was wrong' do
      ws = workspace(account: 'akeyless-development', registry: registry)
      v = described_class.check(ws, sts: -> { '980459274626' })

      expect(v.state).to eq(:mismatch)
      expect(v.message).to include('376129857990')   # what it should have been
      expect(v.message).to include('980459274626')   # what it actually was
      expect(v.message).to include('AWS_PROFILE=akeyless-development')
    end
  end

  describe 'the passing case' do
    it 'permits a matching account' do
      ws = workspace(account: 'akeyless-development', registry: registry)

      expect {
        described_class.assert!(ws, sts: -> { '376129857990' })
      }.not_to raise_error
    end

    # ★ CONTROL. A guard that refused everything would also have "caught" the
    # incident, so the passing case is what proves it discriminates.
    it 'reports ok, not merely not-raising' do
      ws = workspace(account: 'akeyless-development', registry: registry)
      expect(described_class.check(ws, sts: -> { '376129857990' }).state).to eq(:ok)
    end
  end

  describe 'the cases that must NOT silently pass' do
    it 'refuses a declared account that the registry does not define' do
      # A typo'd account name resolves to nothing. Skipping the check for it
      # would reopen the exact hole the guard closes.
      ws = workspace(account: 'akeyless-developmnet', registry: registry)

      expect {
        described_class.assert!(ws, sts: -> { '376129857990' })
      }.to raise_error(described_class::AccountMismatch, /no such entry exists/)
    end

    it 'refuses when the ambient identity cannot be read' do
      # "could not verify" is not "verified". Degrading to allow here is how a
      # guard becomes decorative.
      ws = workspace(account: 'akeyless-development', registry: registry)

      expect {
        described_class.assert!(ws, sts: -> { nil })
      }.to raise_error(described_class::AccountMismatch, /could not read the ambient AWS identity/)
    end

    it 'refuses an empty identity too, not just a nil one' do
      ws = workspace(account: 'akeyless-development', registry: registry)

      expect {
        described_class.assert!(ws, sts: -> { '' })
      }.to raise_error(described_class::AccountMismatch)
    end
  end

  describe 'the deliberate gap' do
    # `account:` is optional today, so an undeclared workspace cannot be
    # checked. It SKIPS rather than refuses — making it mandatory here would
    # break every workspace that never declared one. Stated, not hidden:
    # `pending-pangea-account-mandatory`.
    it 'skips a workspace that declares no account, and says so' do
      ws = workspace(account: nil, registry: registry)
      v = described_class.check(ws, sts: -> { '980459274626' })

      expect(v.state).to eq(:skipped)
      expect(v.message).to include('no `account:` declared')
    end
  end

  describe 'registry resolution' do
    it 'finds the accounts registry in a pangea.yml ABOVE the workspace' do
      # The registry is conventionally declared once at the repo root, not in
      # each workspace — so an upward search is the whole mechanism, and a
      # guard that only looked in the workspace dir would find nothing and
      # refuse every real workspace.
      ws = workspace(account: 'akeyless-staging', registry: registry)
      expect(described_class.account_id_for('akeyless-staging', ws)).to eq('980459274626')
    end

    it 'returns nil for a name no pangea.yml defines' do
      ws = workspace(account: 'akeyless-development', registry: registry)
      expect(described_class.account_id_for('nope', ws)).to be_nil
    end
  end
end
