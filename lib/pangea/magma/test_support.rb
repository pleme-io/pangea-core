# frozen_string_literal: true

require 'fileutils'
require 'json'
require 'tmpdir'

require_relative '../magma'

module Pangea
  module Magma
    # Reusable test scaffolding for Pangea::Magma-driven rspec suites.
    # Centralizes the four patterns every magma integration spec ends
    # up needing:
    #
    #   1. Skip-when-magma-not-installed — `TestSupport.skip_unless_installed!`
    #   2. Minimal `.tf.json` rendering — `TestSupport.render_minimal_workspace`
    #   3. Two-workspace chain fixture — `TestSupport.two_workspace_chain`
    #   4. Tempdir teardown — yield-based scope so cleanup is automatic
    #
    # Example:
    #
    #   require 'pangea/magma/test_support'
    #
    #   RSpec.describe 'something' do
    #     before(:all) { Pangea::Magma::TestSupport.skip_unless_installed!(self) }
    #
    #     it 'plans cleanly' do
    #       Pangea::Magma::TestSupport.with_two_workspace_chain do |chain, dirs|
    #         report = chain.reconcile_all
    #         expect(report['workspaces'].size).to eq(2)
    #       end
    #     end
    #   end
    module TestSupport
      class << self
        # Skip the current rspec example if the magma binary is not on
        # PATH. Pass `self` from a `before(:all)` block.
        def skip_unless_installed!(example_group)
          example_group.skip 'magma not installed' unless Pangea::Magma.installed?
        end

        # Render a minimal Pangea-shaped `.tf.json` file at the given
        # directory. `outputs:` is an optional hash of name → value.
        def render_minimal_workspace(dir, resource_type:, resource_name: 'r',
                                     attributes: {}, outputs: {})
          FileUtils.mkdir_p(dir)
          body = {
            provider: { aws: { region: 'us-east-1' } },
            resource: { resource_type => { resource_name => attributes } },
          }
          body[:output] = outputs.transform_values { |v| { value: v } } unless outputs.empty?
          File.write(File.join(dir, 'main.tf.json'), JSON.pretty_generate(body))
          dir
        end

        # Yield a (Chain, { vpc:, cluster: }) pair for a canonical
        # 2-workspace chain. Cleans up tempdirs automatically.
        def with_two_workspace_chain
          require 'pangea/magma/chain'
          require 'pangea/magma/workspace'

          Dir.mktmpdir('magma-ts') do |tmp|
            vpc_dir     = File.join(tmp, 'vpc')
            cluster_dir = File.join(tmp, 'cluster')

            render_minimal_workspace(vpc_dir,
              resource_type: 'aws_vpc',
              attributes:    { cidr_block: '10.0.0.0/16' },
              outputs:       { vpc_id: 'vpc-test-support' })
            render_minimal_workspace(cluster_dir,
              resource_type: 'aws_iam_role',
              attributes:    { name: 'magma-ts-node' })

            vpc = Pangea::Magma::Workspace.declare(
              name: :vpc, template: 'noop.rb', workspace_dir: vpc_dir,
              outputs: { vpc_id: { type: String } },
            )
            cluster = Pangea::Magma::Workspace.declare(
              name: :cluster, template: 'noop.rb', workspace_dir: cluster_dir,
              inputs: { vpc_id: { type: String } },
            )
            chain = Pangea::Magma::Chain.build do |c|
              c.workspace vpc
              c.workspace cluster
              c.edge from: vpc, output: :vpc_id, to: cluster, input: :vpc_id
            end

            yield chain, { vpc: vpc_dir, cluster: cluster_dir }
          end
        end
      end
    end
  end
end
