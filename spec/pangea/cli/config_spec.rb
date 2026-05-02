# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'
require 'fileutils'
require 'pangea/cli/config'

RSpec.describe Pangea::CLI::Config do
  # Each test gets an isolated tmp tree representing a `repo/workspaces/<ws>`
  # layout: a root pangea.yml with `state.s3.*` defaults plus a workspace
  # pangea.yml that may use `${VAR}` interpolation in its state.key.
  # Mirrors the real shape so the boundary-walking logic in
  # `find_root_pangea_dir` exercises the production path.
  def with_workspace(workspace_yaml:, root_yaml: default_root_yaml, &block)
    Dir.mktmpdir do |root|
      File.write(File.join(root, 'pangea.yml'), root_yaml)
      ws_dir = File.join(root, 'workspaces', 'platform-dns')
      FileUtils.mkdir_p(ws_dir)
      File.write(File.join(ws_dir, 'pangea.yml'), workspace_yaml)
      template = File.join(ws_dir, 'platform_dns.rb')
      FileUtils.touch(template)
      block.call(template)
    end
  end

  def default_root_yaml
    <<~YAML
      state:
        s3:
          bucket: pleme-dev-terraform-state
          region: us-east-1
          dynamodb_table: pleme-dev-terraform-locks
    YAML
  end

  def workspace_yaml(key: 'pangea/platform-dns')
    <<~YAML
      workspace: platform-dns
      default_namespace: development
      namespaces:
        development:
          state:
            type: s3
            key: #{key}
    YAML
  end

  describe '#resolve_backend_config — plain key' do
    it 'produces the expected key for a literal (non-templated) state.key' do
      with_workspace(workspace_yaml: workspace_yaml(key: 'pangea/platform-dns')) do |tpl|
        cfg = described_class.new(tpl, namespace: 'development')
        expect(cfg.backend_config.dig('s3', 'key'))
          .to eq('pangea/platform-dns/platform_dns/terraform.tfstate')
      end
    end
  end

  describe '#resolve_backend_config — ${VAR} interpolation' do
    it 'substitutes ${VAR} from the process environment' do
      with_workspace(workspace_yaml: workspace_yaml(key: 'pangea/platform-dns/${PLATFORM}')) do |tpl|
        ENV['PLATFORM'] = 'pleme'
        cfg = described_class.new(tpl, namespace: 'development')
        expect(cfg.backend_config.dig('s3', 'key'))
          .to eq('pangea/platform-dns/pleme/platform_dns/terraform.tfstate')
      ensure
        ENV.delete('PLATFORM')
      end
    end

    it 'isolates state across two values of the same env var' do
      with_workspace(workspace_yaml: workspace_yaml(key: 'pangea/platform-dns/${PLATFORM}')) do |tpl|
        ENV['PLATFORM'] = 'pleme'
        pleme_key = described_class.new(tpl, namespace: 'development').backend_config.dig('s3', 'key')
        ENV['PLATFORM'] = 'quero'
        quero_key = described_class.new(tpl, namespace: 'development').backend_config.dig('s3', 'key')
        expect(pleme_key).not_to eq(quero_key)
        expect(pleme_key).to include('/pleme/')
        expect(quero_key).to include('/quero/')
      ensure
        ENV.delete('PLATFORM')
      end
    end

    it 'raises when a ${VAR} reference has no env value' do
      with_workspace(workspace_yaml: workspace_yaml(key: 'pangea/platform-dns/${PLATFORM}')) do |tpl|
        ENV.delete('PLATFORM')
        expect {
          described_class.new(tpl, namespace: 'development')
        }.to raise_error(/state\.key references \$\{PLATFORM\} but the env is unset/)
      end
    end

    it 'raises when ${VAR} resolves to an empty string' do
      with_workspace(workspace_yaml: workspace_yaml(key: 'pangea/platform-dns/${PLATFORM}')) do |tpl|
        ENV['PLATFORM'] = ''
        expect {
          described_class.new(tpl, namespace: 'development')
        }.to raise_error(/state\.key references \$\{PLATFORM\} but the env is unset/)
      ensure
        ENV.delete('PLATFORM')
      end
    end

    it 'is concept-agnostic — substitutes any env var, not just PLATFORM' do
      with_workspace(workspace_yaml: workspace_yaml(key: 'pangea/${TENANT}/region/${REGION}')) do |tpl|
        ENV['TENANT'] = 'acme'
        ENV['REGION'] = 'us-east-1'
        cfg = described_class.new(tpl, namespace: 'development')
        expect(cfg.backend_config.dig('s3', 'key'))
          .to eq('pangea/acme/region/us-east-1/platform_dns/terraform.tfstate')
      ensure
        ENV.delete('TENANT')
        ENV.delete('REGION')
      end
    end
  end

  describe '#resolve_backend_config — leaves non-templated keys unaffected' do
    it 'does not touch keys that contain no ${VAR} markers, regardless of env vars set' do
      with_workspace(workspace_yaml: workspace_yaml(key: 'pangea/cloudflare-pleme')) do |tpl|
        ENV['PLATFORM'] = 'pleme' # would have segmented under the old design
        cfg = described_class.new(tpl, namespace: 'development')
        expect(cfg.backend_config.dig('s3', 'key'))
          .to eq('pangea/cloudflare-pleme/platform_dns/terraform.tfstate')
      ensure
        ENV.delete('PLATFORM')
      end
    end
  end
end
