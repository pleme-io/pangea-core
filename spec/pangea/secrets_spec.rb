# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'
require 'fileutils'

RSpec.describe Pangea::Secrets do
  before { described_class.reset! }

  describe '.configure' do
    it 'sets custom sops_file path' do
      described_class.configure(sops_file: '/custom/secrets.yaml')
      expect(described_class.send(:sops_file)).to eq('/custom/secrets.yaml')
    end

    it 'sets custom sops_nix_dir path' do
      described_class.configure(sops_nix_dir: '/custom/sops-nix')
      expect(described_class.send(:sops_nix_dir)).to eq('/custom/sops-nix')
    end
  end

  describe '.resolve' do
    context 'from environment variable' do
      it 'resolves from ENV (highest priority)' do
        ENV['PORKBUN_API_KEY'] = 'env-value'
        expect(described_class.resolve('porkbun/api-key')).to eq('env-value')
      ensure
        ENV.delete('PORKBUN_API_KEY')
      end

      it 'uses custom env var name when specified' do
        ENV['MY_CUSTOM_VAR'] = 'custom-env'
        expect(described_class.resolve('some/path', env: 'MY_CUSTOM_VAR')).to eq('custom-env')
      ensure
        ENV.delete('MY_CUSTOM_VAR')
      end

      it 'skips empty ENV values' do
        ENV['PORKBUN_API_KEY'] = ''
        described_class.configure(sops_file: '/nonexistent', sops_nix_dir: '/nonexistent')
        expect {
          described_class.resolve('porkbun/api-key')
        }.to raise_error(Pangea::Secrets::ResolutionError)
      ensure
        ENV.delete('PORKBUN_API_KEY')
      end
    end

    context 'from sops-nix file' do
      it 'resolves from sops-nix pre-decrypted file' do
        Dir.mktmpdir do |dir|
          secret_dir = File.join(dir, 'porkbun')
          FileUtils.mkdir_p(secret_dir)
          File.write(File.join(secret_dir, 'api-key'), "sops-nix-value\n")

          described_class.configure(sops_nix_dir: dir, sops_file: '/nonexistent')
          expect(described_class.resolve('porkbun/api-key')).to eq('sops-nix-value')
        end
      end

      it 'strips whitespace from sops-nix files' do
        Dir.mktmpdir do |dir|
          secret_dir = File.join(dir, 'test')
          FileUtils.mkdir_p(secret_dir)
          File.write(File.join(secret_dir, 'key'), "  value-with-spaces  \n")

          described_class.configure(sops_nix_dir: dir, sops_file: '/nonexistent')
          expect(described_class.resolve('test/key')).to eq('value-with-spaces')
        end
      end
    end

    context 'priority order' do
      it 'ENV wins over sops-nix file' do
        Dir.mktmpdir do |dir|
          secret_dir = File.join(dir, 'test')
          FileUtils.mkdir_p(secret_dir)
          File.write(File.join(secret_dir, 'key'), 'file-value')

          described_class.configure(sops_nix_dir: dir)
          ENV['TEST_KEY'] = 'env-value'
          expect(described_class.resolve('test/key')).to eq('env-value')
        ensure
          ENV.delete('TEST_KEY')
        end
      end
    end

    context 'required vs optional' do
      before do
        described_class.configure(sops_file: '/nonexistent', sops_nix_dir: '/nonexistent')
      end

      it 'raises ResolutionError when required and not found' do
        expect {
          described_class.resolve('missing/secret')
        }.to raise_error(Pangea::Secrets::ResolutionError, /missing\/secret/)
      end

      it 'includes all attempted paths in error message' do
        expect {
          described_class.resolve('missing/secret')
        }.to raise_error(Pangea::Secrets::ResolutionError, /ENV\[MISSING_SECRET\]/)
      end
    end
  end

  describe '.resolve_optional' do
    it 'returns nil when not found' do
      described_class.configure(sops_file: '/nonexistent', sops_nix_dir: '/nonexistent')
      expect(described_class.resolve_optional('missing/secret')).to be_nil
    end

    it 'returns value when found' do
      ENV['FOUND_KEY'] = 'found-value'
      expect(described_class.resolve_optional('found/key')).to eq('found-value')
    ensure
      ENV.delete('FOUND_KEY')
    end
  end

  describe '.exists?' do
    it 'returns true when secret exists' do
      ENV['EXISTS_TEST'] = 'yes'
      expect(described_class.exists?('exists/test')).to be true
    ensure
      ENV.delete('EXISTS_TEST')
    end

    it 'returns false when secret does not exist' do
      described_class.configure(sops_file: '/nonexistent', sops_nix_dir: '/nonexistent')
      expect(described_class.exists?('nope/missing')).to be false
    end
  end

  describe 'path conversions' do
    it 'converts path to env var: porkbun/api-key → PORKBUN_API_KEY' do
      expect(described_class.send(:path_to_env_var, 'porkbun/api-key')).to eq('PORKBUN_API_KEY')
    end

    it 'converts path to env var: clusters/ryn-builder/age-key → CLUSTERS_RYN_BUILDER_AGE_KEY' do
      expect(described_class.send(:path_to_env_var, 'clusters/ryn-builder/age-key')).to eq('CLUSTERS_RYN_BUILDER_AGE_KEY')
    end

    it 'converts path to SOPS extract: porkbun/api-key → ["porkbun"]["api-key"]' do
      expect(described_class.send(:path_to_sops_extract, 'porkbun/api-key')).to eq('["porkbun"]["api-key"]')
    end

    it 'converts deep path: a/b/c → ["a"]["b"]["c"]' do
      expect(described_class.send(:path_to_sops_extract, 'a/b/c')).to eq('["a"]["b"]["c"]')
    end
  end

  describe '.reset!' do
    it 'clears configuration' do
      described_class.configure(sops_file: '/custom', sops_nix_dir: '/custom')
      described_class.reset!
      expect(described_class.instance_variable_get(:@sops_file)).to be_nil
      expect(described_class.instance_variable_get(:@sops_nix_dir)).to be_nil
    end
  end
end
