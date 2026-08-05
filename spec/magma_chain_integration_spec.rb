# frozen_string_literal: true

require 'pangea/magma/test_support'
# Chain is not loaded by test_support, nor by pangea/magma.rb (which requires
# only magma/runner), so the spec must declare its own dependency.
require 'pangea/magma/chain'

# M0.1 — Chain.reconcile_all integration test. Builds a 2-workspace
# chain via the shared TestSupport helper and drives `magma flow run`
# through Chain.reconcile_all. Verifies that the parsed
# AggregateReport contains both workspaces in topological order and
# the upstream output flowed to the downstream input.
RSpec.describe Pangea::Magma::Chain, 'reconcile_all against magma flow' do
  Pangea::Magma::TestSupport.skip_unless_installed!(self)

  it 'reconciles topologically and propagates outputs' do
    Pangea::Magma::TestSupport.with_two_workspace_chain do |chain, _dirs|
      report = chain.reconcile_all
      expect(report['workspaces'].map { |w| w['workspace'] }).to eq(%w[vpc cluster])
      expect(report['propagated']['cluster.vpc_id']).to eq('vpc-test-support')
    end
  end
end
