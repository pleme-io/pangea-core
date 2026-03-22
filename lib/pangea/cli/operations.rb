# frozen_string_literal: true

require 'json'

module Pangea
  class CLI
    # Runs tofu operations (init, plan, apply, destroy, output)
    # against the synthesized Terraform JSON in the workspace directory.
    class Operations
      attr_reader :config

      TOFU = 'tofu'

      def initialize(config)
        @config = config
        @synthesizer = Synthesizer.new(config)
      end

      # Synthesize template to JSON and write to workspace.
      # @param json_output [Boolean] if true, also print JSON to stdout
      # @return [String] path to the written .tf.json file
      def synth(json_output: false)
        manifest = @synthesizer.synthesize
        output_path = File.join(config.workspace_dir, "#{config.template_name}.tf.json")
        File.write(output_path, JSON.pretty_generate(manifest))
        $stderr.puts "[pangea] Wrote #{output_path}"
        $stdout.puts JSON.pretty_generate(manifest) if json_output
        output_path
      end

      def plan
        synth
        in_workspace do
          tofu_init
          tofu('plan', '-input=false', '-no-color')
        end
      end

      def apply
        synth
        in_workspace do
          tofu_init
          tofu('apply', '-auto-approve', '-input=false', '-no-color')
        end
      end

      def destroy
        synth
        in_workspace do
          tofu_init
          tofu('destroy', '-auto-approve', '-input=false', '-no-color')
        end
      end

      def init
        synth
        in_workspace { tofu_init }
      end

      def output
        Dir.chdir(config.workspace_dir) do
          exec(TOFU, 'output', '-json')
        end
      end

      private

      def in_workspace(&block)
        Dir.chdir(config.workspace_dir, &block)
      end

      def tofu_init
        $stderr.puts "[pangea] Running tofu init..."
        tofu('init', '-input=false', '-no-color', '-reconfigure')
      end

      def tofu(*args)
        success = system(TOFU, *args)
        raise "[pangea] tofu #{args.first} failed" unless success

        success
      end
    end
  end
end
