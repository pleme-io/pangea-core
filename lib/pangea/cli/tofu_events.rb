# frozen_string_literal: true

require 'json'

module Pangea
  class CLI
    # Parses and renders the NDJSON event stream from
    # `tofu plan -json` / `tofu apply -json` / `tofu destroy -json`.
    #
    # OpenTofu's -json flag emits one JSON object per line. Each event has
    # `@level`, `@message`, `@timestamp`, and `type` fields, plus
    # type-specific payload. Parsing the stream structurally (instead of
    # grep'ing human-readable output) lets us:
    #
    # - Filter deprecation warnings (inline_policy, etc.) by matching on
    #   diagnostic.summary, not by string regex over arbitrary output.
    # - Classify errors as transient (eventual consistency, throttling,
    #   service unavailable) vs permanent, by inspecting diagnostic.detail.
    # - Render a clean, consistent human summary across plan / apply /
    #   destroy without provider-specific noise.
    # - Feed the event stream into higher-level orchestration (audit logs,
    #   retry decisions, telemetry) as a typed data structure.
    #
    # When `PANGEA_VERBOSE=1` is set, operations.rb bypasses this module
    # and runs tofu in pass-through mode for full debug output.
    module TofuEvents
      # Diagnostic message patterns that indicate a transient failure —
      # safe to retry. We match against both `summary` and `detail`.
      TRANSIENT_ERROR_PATTERNS = [
        /NoSuchEntity/,          # IAM eventual consistency (role not yet visible)
        /InvalidClientTokenId/,  # IAM creds not yet propagated
        /Throttling/,            # API rate limit
        /RequestLimitExceeded/,  # API rate limit
        /RequestTimeout/,        # Transient timeout
        /InternalFailure/,       # AWS internal
        /ServiceUnavailable/,    # Service outage
      ].freeze

      # Warning summaries to drop from human output. These are known,
      # understood, and not actionable at the user level.
      DROPPED_WARNING_PATTERNS = [
        /inline_policy is deprecated/,
        /Argument is deprecated/,
      ].freeze

      # ACTION_SYMBOLS maps OpenTofu `change.action` to a terse glyph.
      ACTION_SYMBOLS = {
        'create'   => '+',
        'update'   => '~',
        'delete'   => '-',
        'replace'  => '±',
        'read'     => '>',
        'no-op'    => '=',
        'import'   => '→',
      }.freeze

      # One parsed event from the NDJSON stream.
      class Event
        attr_reader :raw

        def initialize(hash)
          @raw = hash
        end

        def type        = @raw['type']
        def level       = @raw['@level']
        def message     = @raw['@message']
        def timestamp   = @raw['@timestamp']
        def diagnostic  = @raw['diagnostic']
        def hook        = @raw['hook']
        def change      = @raw['change']
        def changes     = @raw['changes']
        def operation   = @raw['operation']

        def diagnostic? = type == 'diagnostic'

        def transient_error?
          return false unless diagnostic?
          d = diagnostic
          return false if d.nil? || d['severity'] != 'error'
          blob = "#{d['summary']} #{d['detail']}"
          TRANSIENT_ERROR_PATTERNS.any? { |p| blob.match?(p) }
        end

        def dropped_warning?
          return false unless diagnostic?
          d = diagnostic
          return false if d.nil? || d['severity'] != 'warning'
          summary = d['summary'].to_s
          DROPPED_WARNING_PATTERNS.any? { |p| summary.match?(p) }
        end

        def resource_address
          (hook || {}).dig('resource', 'addr') \
            || (change || {}).dig('resource', 'addr')
        end
      end

      # Accumulates events and exposes summary information.
      class Collector
        attr_reader :events, :transient_errors,
                    :plan_summary, :apply_summary,
                    :dropped_warnings

        def initialize
          @events = []
          @transient_errors = []
          @dropped_warnings = []
          @plan_summary = nil
          @apply_summary = nil
        end

        def consume(event)
          @events << event
          @transient_errors << event if event.transient_error?
          @dropped_warnings << event if event.dropped_warning?

          if event.type == 'change_summary'
            changes = event.changes || {}
            # OpenTofu emits `operation` inside the `changes` hash, not at
            # event root. Fall back to top-level for forward compat.
            op = changes['operation'] || event.operation
            if op == 'plan'
              @plan_summary = changes
            elsif op == 'apply'
              @apply_summary = changes
            end
          end
        end

        def any_transient_errors? = !@transient_errors.empty?

        def summary_line
          if @apply_summary
            a, c, r = @apply_summary.values_at('add', 'change', 'remove').map(&:to_i)
            "Apply: #{a} added, #{c} changed, #{r} destroyed"
          elsif @plan_summary
            a, c, r = @plan_summary.values_at('add', 'change', 'remove').map(&:to_i)
            if (a + c + r).zero?
              'Plan: No changes.'
            else
              "Plan: #{a} to add, #{c} to change, #{r} to destroy"
            end
          end
        end
      end

      module_function

      # Render a single event as a one-line human-readable string, or nil
      # if the event is not user-facing (dropped warnings, internal logs).
      # Callers typically do: `io.puts(render_human(event)) if render_human(event)`.
      def render_human(event)
        return nil if event.dropped_warning?

        case event.type
        when 'version', 'log', 'change_summary'
          nil
        when 'planned_change'
          action = event.change&.dig('action')
          addr = event.resource_address
          return nil unless action && addr
          "  #{ACTION_SYMBOLS.fetch(action, '?')} #{addr}"
        when 'apply_start'
          addr = event.resource_address
          addr ? "  ➜ #{addr}" : nil
        when 'apply_complete'
          addr = event.resource_address
          addr ? "  ✔ #{addr}" : nil
        when 'apply_errored'
          addr = event.resource_address
          err = event.hook&.dig('error')
          "  ✗ #{addr}#{err ? ": #{err}" : ''}"
        when 'diagnostic'
          d = event.diagnostic
          return nil if d.nil?
          sev = d['severity'].to_s.upcase
          lines = ["[#{sev}] #{d['summary']}"]
          lines << "  #{d['detail']}" if d['detail'] && !d['detail'].empty?
          lines.join("\n")
        else
          event.message if event.level != 'info'
        end
      end

      # Parse one NDJSON line. Returns an Event, or nil if the line is not
      # valid JSON (tofu sometimes emits non-JSON prelude lines — notably
      # the "Initializing the backend..." text during `tofu init` which
      # doesn't support -json).
      def parse_line(line)
        return nil if line.nil? || line.empty?
        Event.new(JSON.parse(line))
      rescue JSON::ParserError
        nil
      end

      # Run `cmd` with args, streaming -json output. Yields each Event to
      # the block if given, otherwise collects silently. Returns the
      # Collector regardless. Exit status is available via $?.
      def stream(cmd, args)
        collector = Collector.new
        IO.popen([cmd, *args], err: %i[child out]) do |io|
          io.each_line do |line|
            line = line.chomp
            event = parse_line(line)
            if event.nil?
              # Non-JSON passthrough (rare, but tofu init etc. may emit
              # human-readable text before the JSON stream begins).
              yield_raw(line) if block_given?
              next
            end
            collector.consume(event)
            yield event if block_given?
          end
        end
        collector
      end

      # Helper for yield_raw — overridable in specs. Default: echo to stderr.
      def yield_raw(line)
        $stderr.puts line unless line.strip.empty?
      end
    end
  end
end
