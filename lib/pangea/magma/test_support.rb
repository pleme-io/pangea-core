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

        # Build an arbitrary chain over a tempdir-backed workspace
        # set. `specs` is an Array of:
        #
        #   { name: :vpc, resource_type: 'aws_vpc',
        #     attributes: { ... }, outputs: { vpc_id: 'vpc-x' },
        #     workspace_outputs: { vpc_id: { type: String } },
        #     workspace_inputs:  {} }
        #
        # `edges` is the same shape Pangea::Magma::Chain.edge accepts.
        # Cleans up tempdirs automatically; yields (chain, dirs Hash).
        def with_chain(workspaces:, edges: [])
          require 'pangea/magma/chain'
          require 'pangea/magma/workspace'

          Dir.mktmpdir('magma-chain') do |tmp|
            dirs = {}
            declared = {}

            workspaces.each do |spec|
              name = spec.fetch(:name)
              dir  = File.join(tmp, name.to_s)
              render_minimal_workspace(dir,
                resource_type: spec.fetch(:resource_type, 'aws_iam_role'),
                resource_name: spec.fetch(:resource_name, 'r'),
                attributes:    spec.fetch(:attributes, {}),
                outputs:       spec.fetch(:outputs,    {}))
              dirs[name] = dir
              declared[name] = Pangea::Magma::Workspace.declare(
                name: name, template: 'noop.rb', workspace_dir: dir,
                inputs:  spec.fetch(:workspace_inputs,  {}),
                outputs: spec.fetch(:workspace_outputs, {}),
              )
            end

            chain = Pangea::Magma::Chain.build do |c|
              declared.each_value { |w| c.workspace w }
              edges.each do |e|
                c.edge(
                  from:   declared.fetch(e.fetch(:from)),
                  output: e.fetch(:output),
                  to:     declared.fetch(e.fetch(:to)),
                  input:  e.fetch(:input),
                )
              end
            end

            yield chain, dirs
          end
        end

        # Yield a block with a mocked magma binary at `MAGMA_BINARY`.
        # The mocked binary is a tiny shell script that:
        #   * prints `script_stdout` to stdout (default: "{}"),
        #   * exits with `script_exit_code` (default: 0).
        # Useful for unit tests that should not actually invoke the
        # real magma binary. Restores the previous MAGMA_BINARY +
        # memoized `installed?` state when the block returns.
        def mock_magma_binary(script_stdout: '{}', script_exit_code: 0)
          Dir.mktmpdir('magma-mock') do |tmp|
            path = File.join(tmp, 'magma')
            File.write(path, <<~SH)
              #!/usr/bin/env bash
              # Mocked magma binary for tests. Outputs a fixed stdout +
              # exits with a fixed code regardless of argv.
              cat <<'JSON'
              #{script_stdout}
              JSON
              exit #{script_exit_code}
            SH
            FileUtils.chmod('+x', path)

            prev_env = ENV['MAGMA_BINARY']
            Pangea::Magma.reset!
            ENV['MAGMA_BINARY'] = path
            begin
              yield path
            ensure
              ENV['MAGMA_BINARY'] = prev_env
              Pangea::Magma.reset!
            end
          end
        end
      end
    end
  end
end
