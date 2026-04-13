# frozen_string_literal: true

module Pangea
  # Unified secret resolution for Pangea templates.
  #
  # Single interface for all secret access — templates never know (or care)
  # which backend provides the value. Resolution chain is tried in order
  # until one succeeds.
  #
  # Resolution chain (first match wins):
  #   1. Environment variable (CI, manual override)
  #   2. sops-nix pre-decrypted file (darwin-rebuild / nixos-rebuild)
  #   3. SOPS CLI extraction (fallback — requires sops + age key)
  #
  # Usage:
  #   Pangea::Secrets.configure(
  #     sops_file: '/path/to/secrets.yaml',
  #     sops_nix_dir: '~/.config/sops-nix/secrets',
  #   )
  #
  #   api_key = Pangea::Secrets.resolve('porkbun/api-key')
  #   # Tries: ENV['PORKBUN_API_KEY'] → ~/.config/sops-nix/secrets/porkbun/api-key → sops -d
  #
  #   # Or with explicit env var name:
  #   api_key = Pangea::Secrets.resolve('porkbun/api-key', env: 'MY_CUSTOM_VAR')
  #
  module Secrets
    class ResolutionError < StandardError; end

    class << self
      # Configure default paths for secret resolution.
      #
      # @param sops_file [String] Path to SOPS-encrypted secrets file
      # @param sops_nix_dir [String] Directory where sops-nix decrypts files
      def configure(sops_file: nil, sops_nix_dir: nil)
        @sops_file = sops_file || default_sops_file
        @sops_nix_dir = sops_nix_dir || default_sops_nix_dir
      end

      # Resolve a secret by path.
      #
      # @param path [String] Secret path using forward-slash convention (e.g., "porkbun/api-key")
      # @param env [String, nil] Override environment variable name (default: derived from path)
      # @param required [Boolean] Raise if not found (default: true)
      # @return [String] The secret value
      # @raise [ResolutionError] if required and no backend can resolve
      def resolve(path, env: nil, required: true)
        env_var = env || path_to_env_var(path)
        sops_extract = path_to_sops_extract(path)
        nix_file = File.join(sops_nix_dir, path)

        # 1. Environment variable
        val = ENV[env_var]
        return val if val && !val.empty?

        # 2. sops-nix pre-decrypted file
        if File.exist?(nix_file)
          val = File.read(nix_file).strip
          return val unless val.empty?
        end

        # 3. SOPS CLI extraction
        if File.exist?(sops_file)
          result = `sops --decrypt --extract '#{sops_extract}' #{sops_file} 2>/dev/null`
          return result.strip if $?.success? && !result.strip.empty?
        end

        # Not found
        if required
          raise ResolutionError,
            "secret '#{path}' not found in: ENV[#{env_var}], #{nix_file}, SOPS[#{sops_extract}]"
        end

        nil
      end

      # Resolve a secret, returning nil instead of raising.
      #
      # @param path [String] Secret path
      # @param env [String, nil] Override environment variable name
      # @return [String, nil] The secret value or nil
      def resolve_optional(path, env: nil)
        resolve(path, env: env, required: false)
      end

      # Check if a secret exists without retrieving its value.
      #
      # @param path [String] Secret path
      # @return [Boolean]
      def exists?(path)
        !resolve_optional(path).nil?
      end

      # Reset configuration (for testing).
      def reset!
        @sops_file = nil
        @sops_nix_dir = nil
      end

      private

      def sops_file
        @sops_file || default_sops_file
      end

      def sops_nix_dir
        @sops_nix_dir || default_sops_nix_dir
      end

      # Default SOPS file: relative to pangea-architectures workspace convention
      def default_sops_file
        # Try the standard nix repo location
        candidates = [
          File.expand_path('~/code/github/pleme-io/nix/secrets.yaml'),
          File.expand_path('../../../nix/secrets.yaml', __dir__),
        ]
        candidates.find { |f| File.exist?(f) } || 'secrets.yaml'
      end

      # Default sops-nix directory: where darwin-rebuild decrypts secrets
      def default_sops_nix_dir
        File.expand_path('~/.config/sops-nix/secrets')
      end

      # Convert "porkbun/api-key" → "PORKBUN_API_KEY"
      def path_to_env_var(path)
        path.tr('/', '_').tr('-', '_').upcase
      end

      # Convert "porkbun/api-key" → '["porkbun"]["api-key"]'
      def path_to_sops_extract(path)
        path.split('/').map { |p| "[\"#{p}\"]" }.join
      end
    end
  end
end
