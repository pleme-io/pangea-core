# frozen_string_literal: true

require 'json'

module Pangea
  class CLI
    # Synthesizes a Pangea Ruby template into Terraform JSON.
    # Loads the template, evaluates it on a TerraformSynthesizer,
    # injects the backend config, and returns the manifest.
    class Synthesizer
      attr_reader :config

      def initialize(config)
        @config = config
      end

      # @return [Hash] Normalized Terraform manifest with string keys
      def synthesize
        load_workspace_libs
        load_synthesizer_gem

        synth = TerraformSynthesizer.new
        block = capture_template_block(config.template_content, config.template_file)

        if block
          synth.instance_eval(&block)
        else
          $stderr.puts "[pangea] Warning: no template block found, trying direct eval"
          synth.instance_eval(config.template_content, config.template_file)
        end

        manifest = normalize(synth.synthesis)
        inject_backend(manifest)
        manifest
      end

      private

      def load_workspace_libs
        [config.template_dir, Dir.pwd].uniq.each do |dir|
          lib_dir = File.join(dir, 'lib')
          $LOAD_PATH.unshift(lib_dir) if File.directory?(lib_dir) && !$LOAD_PATH.include?(lib_dir)
        end

        # Auto-require architecture modules if available
        %w[pangea/architectures pangea/workspace_config].each do |mod|
          require mod
        rescue LoadError
          nil # Optional — not all workspaces have these
        end
      end

      def load_synthesizer_gem
        require 'terraform-synthesizer'
      rescue LoadError
        begin
          require 'terraform_synthesizer'
        rescue LoadError
          require 'abstract-synthesizer'
        end
      end

      # Captures the block from the template file. Two DSL surfaces
      # are supported in parallel:
      #
      #   template :name do … end         — original; intercepts via
      #                                     Kernel#template override.
      #   Pangea.architecture 'name' do … end
      #                                   — abstract concept; block
      #                                     lands in
      #                                     Pangea.last_architecture.
      #
      # When both are present in the same file the ``template``
      # override takes precedence (it runs first during eval); the
      # architecture fallback catches templates that never call
      # ``template`` explicitly.
      def capture_template_block(content, file_path)
        captured = nil
        original = method(:template) if respond_to?(:template, true)

        define_singleton_method(:template) { |_name, &blk| captured = blk }

        # Reset the architecture registry's last-declared pointer so
        # we don't accidentally pick up a leftover from a previous
        # template's eval in the same process (tests, bulk mode).
        Pangea.reset_architectures! if Pangea.respond_to?(:reset_architectures!)

        eval(content, binding, file_path) # rubocop:disable Security/Eval

        # Restore original method if it existed
        if original
          define_singleton_method(:template, original)
        else
          singleton_class.remove_method(:template) if singleton_class.method_defined?(:template)
        end

        captured || Pangea.last_architecture&.block
      end

      # JSON round-trip to normalize symbol keys → string keys
      def normalize(manifest)
        JSON.parse(JSON.generate(manifest))
      end

      def inject_backend(manifest)
        return if config.backend_config.empty?

        manifest['terraform'] ||= {}
        manifest['terraform']['backend'] = config.backend_config

        # Merge required_providers from template if present
        # (templates set this via `terraform required_providers: {...}`)
        if manifest.dig('terraform', 'required_providers').nil? &&
           manifest.key?('terraform') &&
           manifest['terraform'].is_a?(Hash)
          # Already handled — required_providers preserved from synthesis
        end
      end
    end
  end
end
