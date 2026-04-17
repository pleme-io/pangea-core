# frozen_string_literal: true

require 'yaml'
require 'fileutils'

module Pangea
  class CLI
    # Resolves workspace configuration from pangea.yml files.
    # Handles namespace resolution, state backend config, and workspace paths.
    class Config
      attr_reader :template_file, :template_dir, :template_name,
                  :namespace, :workspace_dir, :backend_config

      def initialize(template_file, namespace: nil)
        @template_file = File.expand_path(template_file)
        @template_dir = File.dirname(@template_file)
        @template_name = File.basename(@template_file, '.rb')
        @namespace = resolve_namespace(namespace)
        @workspace_dir = build_workspace_dir
        @backend_config = resolve_backend_config
      end

      def template_content
        @template_content ||= File.read(@template_file)
      end

      private

      def resolve_namespace(explicit)
        return explicit if explicit && !explicit.empty?

        load_default_namespace || 'default'
      end

      def load_default_namespace
        # Check workspace pangea.yml first, fall back to root
        [@template_dir, Dir.pwd].uniq.each do |dir|
          yml = find_pangea_yml(dir)
          next unless yml

          config = YAML.safe_load(File.read(yml)) || {}
          return config['default_namespace'] if config['default_namespace']
        end
        nil
      end

      def build_workspace_dir
        home = ENV.fetch('HOME', '.')
        dir = File.join(home, '.pangea', 'workspaces', @namespace, @template_name)
        FileUtils.mkdir_p(dir)
        dir
      end

      def resolve_backend_config
        # Load root config first, then workspace — workspace wins on conflicts.
        # Use deep_merge so nested keys (namespaces, state) compose correctly.
        # Root is discovered by walking up from the TEMPLATE directory (not
        # pwd) until a directory with pangea.yml that declares state.s3.*
        # defaults is found. This is the same boundary logic WorkspaceConfig
        # uses — the two must agree for backend merging to work. Previously
        # this used Dir.pwd, which silently loaded the workspace's own
        # pangea.yml as "root" when pangea was run from within the workspace,
        # dropping the bucket/region defaults on the floor.
        root_dir = find_root_pangea_dir(@template_dir)
        root_config = root_dir ? (load_pangea_yml(root_dir) || {}) : {}
        ws_config = load_pangea_yml(@template_dir) || {}
        merged = deep_merge(root_config, ws_config)

        ns_config = merged.dig('namespaces', @namespace)
        return {} unless ns_config

        state = ns_config['state'] || {}
        state_type = state['type'] || 's3'
        s3_defaults = merged.dig('state', 's3') || {}

        case state_type
        when 'local'
          { 'local' => { 'path' => state['path'] || 'terraform.tfstate' } }
        when 's3'
          {
            's3' => {
              'bucket' => state['bucket'] || s3_defaults['bucket'],
              'key' => "#{state['key'] || s3_defaults['key']}/#{@template_name}/terraform.tfstate",
              'region' => state['region'] || s3_defaults['region'] || 'us-east-1',
              'dynamodb_table' => state['dynamodb_table'] || s3_defaults['dynamodb_table'],
              'encrypt' => state.fetch('encrypt', s3_defaults.fetch('encrypt', true)),
            }.compact,
          }
        else
          {}
        end
      end

      def find_pangea_yml(dir)
        path = File.join(dir, 'pangea.yml')
        File.exist?(path) ? path : nil
      end

      # Walk up from `start_dir` looking for a pangea.yml that declares
      # top-level `state.s3.*` defaults (the marker of the "true" root).
      # Returns nil if no such file is found before reaching the filesystem
      # root.
      def find_root_pangea_dir(start_dir)
        dir = File.expand_path(start_dir)
        loop do
          yml = find_pangea_yml(dir)
          if yml
            config = YAML.safe_load(File.read(yml)) rescue {}
            # A root pangea.yml declares state.s3.* defaults; workspace-
            # level pangea.yml files declare namespaces[].state.{type,key}
            # but no top-level state.s3 block.
            return dir if config.is_a?(Hash) && config.dig('state', 's3').is_a?(Hash)
          end
          parent = File.dirname(dir)
          return nil if parent == dir
          dir = parent
        end
      end

      def load_pangea_yml(dir)
        path = find_pangea_yml(dir)
        return nil unless path

        YAML.safe_load(File.read(path)) || {}
      rescue StandardError
        nil
      end

      # Recursively merge two hashes — values from `override` win on conflicts.
      def deep_merge(base, override)
        base.merge(override) do |_key, old_val, new_val|
          if old_val.is_a?(Hash) && new_val.is_a?(Hash)
            deep_merge(old_val, new_val)
          else
            new_val
          end
        end
      end
    end
  end
end
