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
        yml = find_pangea_yml(@template_dir)
        return nil unless yml

        config = YAML.safe_load(File.read(yml)) || {}
        config['default_namespace']
      end

      def build_workspace_dir
        home = ENV.fetch('HOME', '.')
        dir = File.join(home, '.pangea', 'workspaces', @namespace, @template_name)
        FileUtils.mkdir_p(dir)
        dir
      end

      def resolve_backend_config
        configs = [@template_dir, Dir.pwd].uniq.filter_map { |dir| load_pangea_yml(dir) }
        merged = configs.reduce({}) { |acc, cfg| acc.merge(cfg) }

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

      def load_pangea_yml(dir)
        path = find_pangea_yml(dir)
        return nil unless path

        YAML.safe_load(File.read(path)) || {}
      rescue StandardError
        nil
      end
    end
  end
end
