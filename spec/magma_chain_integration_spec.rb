# frozen_string_literal: true

require 'tmpdir'
require 'fileutils'
require 'json'
require 'pangea/magma'
require 'pangea/magma/chain'
require 'pangea/magma/workspace'

# M0.1 — Chain.reconcile_all integration test. Builds a 2-workspace
# chain with one cross-workspace edge, renders two Pangea-style
# `.tf.json` files into temp dirs, and drives `magma flow run`
# through Chain.reconcile_all. Verifies that the parsed
# AggregateReport contains both workspaces in topological order and
# the upstream output flowed to the downstream input.
RSpec.describe Pangea::Magma::Chain, 'reconcile_all against magma flow' do
  before(:all) do
    skip 'magma not installed' unless Pangea::Magma.installed?
  end

  let(:tmp_root) { Dir.mktmpdir('magma-chain-int') }
  after { FileUtils.rm_rf(tmp_root) }

  let(:vpc_dir)     { File.join(tmp_root, 'vpc') }
  let(:cluster_dir) { File.join(tmp_root, 'cluster') }

  before do
    FileUtils.mkdir_p(vpc_dir)
    FileUtils.mkdir_p(cluster_dir)

    File.write(File.join(vpc_dir, 'main.tf.json'), JSON.pretty_generate(
      provider: { aws: { region: 'us-east-1' } },
      resource: { aws_vpc: { net: { cidr_block: '10.0.0.0/16' } } },
      output:   { vpc_id: { value: 'vpc-test-1' } },
    ))

    File.write(File.join(cluster_dir, 'main.tf.json'), JSON.pretty_generate(
      provider: { aws: { region: 'us-east-1' } },
      resource: { aws_iam_role: { node: { name: 'magma-test-node' } } },
      output:   { cluster_name: { value: 'magma-test-cluster' } },
    ))
  end

  it 'reconciles topologically and propagates outputs' do
    vpc = Pangea::Magma::Workspace.declare(
      name: :vpc, template: 'noop.rb', workspace_dir: vpc_dir,
      outputs: { vpc_id: { type: String } },
    )
    cluster = Pangea::Magma::Workspace.declare(
      name: :cluster, template: 'noop.rb', workspace_dir: cluster_dir,
      inputs: { vpc_id: { type: String } },
    )
    chain = described_class.build do |c|
      c.workspace vpc
      c.workspace cluster
      c.edge from: vpc, output: :vpc_id, to: cluster, input: :vpc_id
    end

    report = chain.reconcile_all
    expect(report['workspaces'].map { |w| w['workspace'] }).to eq(%w[vpc cluster])
    propagated = report['propagated'] || {}
    expect(propagated['cluster.vpc_id']).to eq('vpc-test-1')
  end
end
