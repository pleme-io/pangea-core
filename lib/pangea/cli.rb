# frozen_string_literal: true

require_relative 'cli/config'
require_relative 'cli/synthesizer'
require_relative 'cli/operations'
require_relative 'cli/cascade'

module Pangea
  # CLI for the Pangea IaC DSL.
  #
  # Synthesizes Ruby templates into Terraform JSON and runs tofu operations.
  #
  #   pangea plan template.rb --namespace development
  #   pangea apply template.rb --namespace production
  #   pangea destroy template.rb --namespace development
  #   pangea synth template.rb  # synthesis only
  #   pangea bulk plan --namespace development  # all .rb templates in cwd
  #
  class CLI
    OPERATIONS = %w[plan apply destroy synth output init bulk].freeze

    HELP = <<~HELP
      Usage: pangea <operation> <template.rb> [--namespace <ns>] [--depth <n>]

      Operations:
        plan       Synthesize + tofu plan
        apply      Synthesize + tofu apply -auto-approve
        destroy    Synthesize + tofu destroy -auto-approve
        synth      Synthesize only (write JSON, no tofu)
        output     Run tofu output -json on existing workspace
        init       Synthesize + tofu init (no plan/apply)
        bulk       Run operation on all .rb templates in a directory

      Bulk usage:
        pangea bulk <operation> [--namespace <ns>] [--dir <path>]

      Options:
        --namespace, -n   Namespace (overrides pangea.yml default_namespace)
        --dir, -d         Directory for bulk operations (default: current dir)
        --depth, -D <n>   Cap cascade depth (0 = seed only, 1 = direct
                          neighbors, nil = unlimited). Default resolves from
                          PANGEA_CASCADE_DEPTH → workspace pangea.yml
                          cascade.default_depth → root pangea.yml same →
                          unlimited.
        --no-cascade      Run seed workspace only; same as PANGEA_NO_CASCADE=1
        --help, -h        Show this help

      Per-workspace cascade actions (pangea.yml `cascade` block):
        default_depth: N               — default depth for this workspace
        pre_actions:  [synth, output, init]  — run before primary command
        post_actions: [synth, output, init]  — run after  primary command
      Note: pre/post actions cannot name plan/apply/destroy/deploy.
    HELP

    class << self
      def run(argv = ARGV.dup)
        operation, template_file, namespace, bulk_dir, options = parse(argv)

        if operation == 'bulk'
          run_bulk(template_file, namespace, bulk_dir)
        else
          run_single(operation, template_file, namespace, options)
        end
      end

      private

      def run_single(operation, template_file, namespace, options = {})
        # plan / apply / destroy on a template that participates in
        # reactive relationships cascades across the constellation in
        # dependency order. Other operations (synth/output/init) stay
        # single-workspace — they don't materially change infra state.
        cascade_ops = %w[plan apply destroy]
        if cascade_ops.include?(operation) && options[:no_cascade] != true
          cascade = Cascade.for_template(template_file, max_depth: options[:depth])
          if cascade
            case operation
            when 'plan'    then return cascade.plan(namespace: namespace)
            when 'apply'   then return cascade.apply(namespace: namespace)
            when 'destroy' then return cascade.destroy(namespace: namespace)
            end
          end
        end

        config = Config.new(template_file, namespace: namespace)
        ops = Operations.new(config)

        case operation
        when 'synth'  then ops.synth(json_output: true)
        when 'plan'   then ops.plan
        when 'apply'  then ops.apply
        when 'destroy' then ops.destroy
        when 'output' then ops.output
        when 'init'   then ops.init
        else raise "Unknown operation: #{operation}"
        end
      end

      def run_bulk(sub_operation, namespace, dir)
        dir ||= Dir.pwd
        templates = Dir.glob(File.join(dir, '*.rb'))

        if templates.empty?
          $stderr.puts "[pangea] No .rb template files found in #{dir}"
          exit 1
        end

        templates.each do |tmpl|
          $stderr.puts "==> #{sub_operation}: #{File.basename(tmpl)}"
          run_single(sub_operation, tmpl, namespace)
        end
      end

      def parse(argv)
        operation = argv.shift

        if operation.nil? || %w[--help -h].include?(operation)
          $stderr.puts HELP
          exit(operation.nil? ? 1 : 0)
        end

        unless OPERATIONS.include?(operation)
          $stderr.puts "Error: unknown operation '#{operation}'"
          $stderr.puts HELP
          exit 1
        end

        namespace = extract_flag(argv, '--namespace', '-n')
        bulk_dir = extract_flag(argv, '--dir', '-d')
        depth_raw = extract_flag(argv, '--depth', '-D')
        no_cascade = extract_switch(argv, '--no-cascade')

        options = {
          depth: parse_depth(depth_raw),
          no_cascade: no_cascade,
        }

        if operation == 'bulk'
          # For bulk: first remaining arg is the sub-operation
          sub_operation = argv.shift
          unless sub_operation && %w[plan apply destroy synth init].include?(sub_operation)
            $stderr.puts "Error: bulk requires a sub-operation (plan, apply, destroy, synth, init)"
            exit 1
          end
          [operation, sub_operation, namespace, bulk_dir, options]
        else
          template_file = argv.shift
          unless template_file
            $stderr.puts "Error: template file required"
            exit 1
          end
          unless File.exist?(template_file)
            $stderr.puts "Error: template file not found: #{template_file}"
            exit 1
          end
          [operation, template_file, namespace, nil, options]
        end
      end

      def extract_flag(argv, long, short)
        idx = argv.index(long) || argv.index(short)
        return nil unless idx

        argv.delete_at(idx) # remove flag
        argv.delete_at(idx) # remove value (now at same index)
      end

      def extract_switch(argv, long)
        idx = argv.index(long)
        return false unless idx

        argv.delete_at(idx)
        true
      end

      # Parse a --depth CLI value. Accepts non-negative ints; rejects
      # garbage with a clear error so users don't silently fall through
      # to "unlimited" on a typo.
      def parse_depth(raw)
        return nil if raw.nil?

        Integer(raw, 10).tap do |n|
          if n.negative?
            $stderr.puts "Error: --depth must be >= 0 (got #{raw})"
            exit 1
          end
        end
      rescue ArgumentError, TypeError
        $stderr.puts "Error: --depth must be an integer (got #{raw.inspect})"
        exit 1
      end
    end
  end
end
