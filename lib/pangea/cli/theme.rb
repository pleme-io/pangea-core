# frozen_string_literal: true

module Pangea
  class CLI
    # Nord-palette ANSI theming for the pangea CLI.
    #
    # Emits 24-bit color escape sequences using the Nord palette
    # (https://www.nordtheme.com/) mapped to semantic roles. Falls back to
    # plain text when:
    #
    # - Neither stdout nor stderr is a TTY (piped / captured output)
    # - `NO_COLOR` is set (https://no-color.org/)
    # - `PANGEA_NO_COLOR` is set
    # - `TERM` is `dumb`
    #
    # Nord palette reference:
    #   Polar Night (backgrounds, muted text):
    #     nord0  #2E3440
    #     nord1  #3B4252
    #     nord2  #434C5E
    #     nord3  #4C566A   ← most-used muted foreground
    #   Snow Storm (foregrounds):
    #     nord4  #D8DEE9
    #     nord5  #E5E9F0
    #     nord6  #ECEFF4   ← brightest fg (resource addresses, headings)
    #   Frost (info / progress / primary accent):
    #     nord7  #8FBCBB   ← headings (teal)
    #     nord8  #88C0D0   ← primary info/progress (cyan)
    #     nord9  #81A1C1   ← paths, secondary (blue)
    #     nord10 #5E81AC   ← backgrounds / rarely used
    #   Aurora (semantic accents):
    #     nord11 #BF616A   ← error (red)
    #     nord12 #D08770   ← destroy (orange)
    #     nord13 #EBCB8B   ← warning, replace, counts (yellow)
    #     nord14 #A3BE8C   ← success, create (green)
    #     nord15 #B48EAD   ← meta, import (purple)
    module Theme
      # rgb triples
      NORD = {
        nord0:  [46,  52,  64],
        nord1:  [59,  66,  82],
        nord2:  [67,  76,  94],
        nord3:  [76,  86,  106],
        nord4:  [216, 222, 233],
        nord5:  [229, 233, 240],
        nord6:  [236, 239, 244],
        nord7:  [143, 188, 187],
        nord8:  [136, 192, 208],
        nord9:  [129, 161, 193],
        nord10: [94,  129, 172],
        nord11: [191, 97,  106],
        nord12: [208, 135, 112],
        nord13: [235, 203, 139],
        nord14: [163, 190, 140],
        nord15: [180, 142, 173],
      }.freeze

      # Semantic role → palette entry.
      SEMANTICS = {
        # Structural
        label:        :nord3,    # "[pangea]" prefix (muted)
        divider:      :nord3,    # horizontal rules, tree glyphs
        heading:      :nord7,    # section titles
        resource:     :nord6,    # resource addresses (brightest fg)
        path:         :nord9,    # file paths
        namespace:    :nord15,   # namespaces / envs
        count:        :nord13,   # numeric counts (emphasis)
        # Status levels
        info:         :nord8,    # neutral info / progress
        success:      :nord14,   # success / create
        warning:      :nord13,   # warning
        error:        :nord11,   # error
        transient:    :nord12,   # transient / retry-worthy error
        deprecation:  :nord3,    # dropped deprecation summary (muted)
        # Change actions
        create:       :nord14,   # + (green)
        update:       :nord8,    # ~ (cyan)
        delete:       :nord11,   # - (red)
        replace:      :nord13,   # ± (yellow)
        read:         :nord9,    # > (blue)
        import:       :nord15,   # → (purple)
        noop:         :nord3,    # = (muted)
      }.freeze

      # Ordered list of roles used to test output is theme-reachable.
      ROLES = SEMANTICS.keys.freeze

      # The blackmatter family marker. Adopted from the blackmatter-shell
      # starship prompt (`[❄](bold #88C0D0)` — Nord frost cyan snowflake).
      # Every pangea-emitted line begins with this glyph, colored by the
      # line's semantic level — visual coherence with the rest of the
      # pleme-io / blackmatter-themed shell.
      MARKER = '❄'

      module_function

      # Whether ANSI is currently enabled (TTY + not disabled by env).
      def enabled?
        return @enabled unless @enabled.nil?
        @enabled = compute_enabled
      end

      # Force-enable (for testing). Pass nil to restore auto-detect.
      def override_enabled(value)
        @enabled = value
      end

      # RGB tuple for a role, or nil if unknown.
      def rgb_for(role)
        NORD[SEMANTICS[role]]
      end

      # Colorise `text` with the given semantic role.
      def color(role, text)
        return text.to_s unless enabled?
        rgb = rgb_for(role)
        return text.to_s unless rgb
        "\e[38;2;#{rgb[0]};#{rgb[1]};#{rgb[2]}m#{text}\e[0m"
      end

      # Bold emphasis.
      def bold(text)
        return text.to_s unless enabled?
        "\e[1m#{text}\e[0m"
      end

      # Dim emphasis.
      def dim(text)
        return text.to_s unless enabled?
        "\e[2m#{text}\e[0m"
      end

      # The marker in its level color — `❄` tinted by semantic role.
      def marker(level: :info)
        bold(color(level, MARKER))
      end

      # Standard pangea-prefixed log line. Emits to stderr by default.
      # `level` is a semantic role (info / success / warning / error) and
      # drives both the snowflake color and the body color.
      def log(message, level: :info, io: $stderr)
        io.puts "#{marker(level: level)} #{color(level, message)}"
      end

      # Structured log with multiple highlighted fragments. Example:
      #
      #   Theme.structured_log(
      #     [:info,      'Synthesizing'],
      #     [:path,      '/path/to/template.rb'],
      #     [:deprecation, 'in namespace'],
      #     [:namespace, 'development'],
      #   )
      #
      # Produces: `❄ Synthesizing /path/to/template.rb in namespace development`
      # with the snowflake in the info color and each token colored per its role.
      def structured_log(*parts, io: $stderr, marker_level: :info)
        body = parts.map { |(role, text)| color(role, text) }.join(' ')
        io.puts "#{marker(level: marker_level)} #{body}"
      end

      # Section divider with snowflake title. Used to separate synth/init/
      # plan/apply phases when the output would otherwise run together.
      # Shape: `❄ title ─────────────────────`
      def section(title, io: $stderr, width: 72, level: :heading)
        label = " #{title} "
        head = "#{marker(level: level)}#{color(level, label)}"
        # account for the marker glyph + space that don't count toward Nord widths
        trailing_len = [width - label.length - 2, 4].max
        trailing = '─' * trailing_len
        io.puts "#{head}#{color(:divider, trailing)}"
      end

      # Action glyph + color for a planned change. Returns a two-character
      # colored string suitable for inline use (e.g., "  #{glyph} addr").
      def action_glyph(action)
        glyph, role = case action
                      when 'create'  then ['+', :create]
                      when 'update'  then ['~', :update]
                      when 'delete'  then ['-', :delete]
                      when 'replace' then ['±', :replace]
                      when 'read'    then ['>', :read]
                      when 'import'  then ['→', :import]
                      when 'no-op'   then ['=', :noop]
                      else                ['?', :info]
                      end
        color(role, glyph)
      end

      # Status glyphs for apply progress (inherit action colors via semantics).
      def progress_glyph = color(:info, '➜')
      def success_glyph  = color(:success, '✔')
      def error_glyph    = color(:error, '✗')

      # Pretty-print a count with semantic color. Zero counts are muted.
      def count(n, role: :count)
        text = n.to_s
        if n.to_i.zero?
          color(:deprecation, text)
        else
          color(role, text)
        end
      end

      class << self
        private

        def compute_enabled
          return false if ENV['NO_COLOR']
          return false if ENV['PANGEA_NO_COLOR']
          return false if ENV['TERM'] == 'dumb'
          $stderr.tty? || $stdout.tty?
        end
      end
    end
  end
end
