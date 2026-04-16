# frozen_string_literal: true

require 'json'
require_relative 'tofu_events'

module Pangea
  class CLI
    # Runs tofu operations (init, plan, apply, destroy, output)
    # against the synthesized Terraform JSON in the workspace directory.
    #
    # By default, plan / apply / destroy use OpenTofu's -json event stream
    # and render a clean human summary via Pangea::CLI::TofuEvents. When
    # `PANGEA_VERBOSE=1` is set, tofu runs in pass-through mode instead.
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
        $stderr.puts "[pangea] Synthesizing #{config.template_file} [namespace: #{config.namespace}]"
        manifest = @synthesizer.synthesize
        json = JSON.pretty_generate(manifest)
        output_path = File.join(config.workspace_dir, "#{config.template_name}.tf.json")
        File.write(output_path, json)
        $stderr.puts "[pangea] Wrote #{output_path}"
        $stdout.puts json if json_output
        output_path
      end

      def plan
        synth
        in_workspace do
          tofu_init
          run_tofu('plan')
        end
      end

      def apply
        synth
        in_workspace do
          tofu_init
          run_tofu('apply', '-auto-approve')
        end
      end

      def destroy
        synth
        in_workspace do
          tofu_init
          run_tofu('destroy', '-auto-approve')
        end
      end

      def init
        synth
        in_workspace { tofu_init }
      end

      def output
        Dir.chdir(config.workspace_dir) do
          tofu('output', '-json')
        end
      end

      private

      def in_workspace(&block)
        Dir.chdir(config.workspace_dir, &block)
      end

      def tofu_init
        # tofu init doesn't support -json — run in pass-through mode.
        $stderr.puts '[pangea] Running tofu init...'
        tofu('init', '-input=false', '-no-color', '-reconfigure')
      end

      # Run plan/apply/destroy in JSON-streamed mode by default, or
      # pass-through if PANGEA_VERBOSE=1.
      def run_tofu(op, *extra_args)
        if verbose_mode?
          tofu(op, '-input=false', '-no-color', *extra_args)
        else
          run_tofu_json(op, *extra_args)
        end
      end

      def verbose_mode?
        ENV['PANGEA_VERBOSE'] == '1'
      end

      # Stream `tofu <op> -json`, filter/render through TofuEvents,
      # and raise on failure. Dropped warnings (inline_policy deprecation,
      # argument deprecation) are summarised at the end, not shown inline.
      def run_tofu_json(op, *extra_args)
        args = [op, '-input=false', '-no-color', '-json', *extra_args]
        collector = TofuEvents.stream(TOFU, args) do |event|
          line = TofuEvents.render_human(event)
          $stderr.puts(line) if line
        end

        unless @dropped_warnings_reported
          dropped_count = collector.dropped_warnings.size
          if dropped_count.positive?
            $stderr.puts "[pangea] #{dropped_count} deprecation warning(s) suppressed (set PANGEA_VERBOSE=1 to show)"
          end
          @dropped_warnings_reported = true
        end

        if (summary = collector.summary_line)
          $stderr.puts "[pangea] #{summary}"
        end

        unless $?.success?
          kind = collector.any_transient_errors? ? 'transient' : 'failed'
          raise "[pangea] tofu #{op} #{kind} (exit #{$?.exitstatus})"
        end
        true
      end

      def tofu(*args)
        success = system(TOFU, *args)
        raise "[pangea] tofu #{args.first} failed" unless success

        success
      end
    end
  end
end
