# frozen_string_literal: true

module Pangea
  # Preset composition for infrastructure configurations.
  #
  # Presets are frozen hashes of configuration overrides that can be composed
  # (stacked) and merged with user config. Later values win.
  #
  # Usage in architectures:
  #
  #   module MyArchitecture
  #     PROFILES = {
  #       dev:        { encryption: 'AES256', versioning: false }.freeze,
  #       production: { encryption: 'aws:kms', versioning: true }.freeze,
  #     }.freeze
  #
  #     def self.build(synth, config = {})
  #       config = Pangea::Presets.apply(config, PROFILES)
  #       # config[:profile] consumed, defaults merged, user overrides on top
  #     end
  #   end
  #
  module Presets
    # Apply a named profile to a config hash.
    #
    # Extracts :profile key from config, looks it up in profiles hash,
    # deep-merges the profile defaults under user config (user wins).
    #
    # @param config [Hash] User configuration (may contain :profile key)
    # @param profiles [Hash] Map of profile name → frozen defaults hash
    # @param default_profile [Symbol] Fallback profile if none specified
    # @return [Hash] Merged config with profile defaults applied
    def self.apply(config, profiles, default_profile: :dev)
      config = config.dup
      profile_name = config.delete(:profile) || default_profile
      profile = profiles[profile_name]

      raise ArgumentError, "Unknown profile :#{profile_name}. Available: #{profiles.keys.join(', ')}" unless profile

      deep_merge(profile, config)
    end

    # Compose multiple preset hashes into one (left-to-right, later wins).
    #
    # @param presets [Array<Hash>] Preset hashes to merge
    # @return [Hash] Composed preset (frozen)
    def self.compose(*presets)
      presets.reduce({}) { |acc, p| deep_merge(acc, p) }.freeze
    end

    # Deep merge two hashes. Values from `overlay` win over `base`.
    # Nested hashes are recursively merged; all other types are replaced.
    #
    # @param base [Hash]
    # @param overlay [Hash]
    # @return [Hash]
    def self.deep_merge(base, overlay)
      base.merge(overlay) do |_key, base_val, overlay_val|
        if base_val.is_a?(Hash) && overlay_val.is_a?(Hash)
          deep_merge(base_val, overlay_val)
        else
          overlay_val
        end
      end
    end
  end
end
