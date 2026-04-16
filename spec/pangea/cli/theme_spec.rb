# frozen_string_literal: true

require 'spec_helper'
require 'pangea/cli/theme'

RSpec.describe Pangea::CLI::Theme do
  around do |ex|
    original_override = described_class.instance_variable_get(:@enabled)
    ex.run
  ensure
    described_class.instance_variable_set(:@enabled, original_override)
  end

  describe 'palette' do
    it 'defines all 16 Nord colors' do
      expect(described_class::NORD.keys).to include(
        :nord0, :nord1, :nord2, :nord3, :nord4, :nord5, :nord6, :nord7,
        :nord8, :nord9, :nord10, :nord11, :nord12, :nord13, :nord14, :nord15
      )
    end

    it 'each palette entry is a 3-element RGB tuple' do
      described_class::NORD.each_value do |rgb|
        expect(rgb).to be_an(Array)
        expect(rgb.size).to eq(3)
        rgb.each { |c| expect(c).to be_between(0, 255) }
      end
    end

    it 'every semantic role maps to a real Nord entry' do
      described_class::SEMANTICS.each_value do |nord_key|
        expect(described_class::NORD).to have_key(nord_key)
      end
    end
  end

  describe '.enabled?' do
    it 'returns false when NO_COLOR is set' do
      stub_const('ENV', ENV.to_h.merge('NO_COLOR' => '1'))
      described_class.override_enabled(nil)
      expect(described_class.enabled?).to be false
    end

    it 'returns false when PANGEA_NO_COLOR is set' do
      stub_const('ENV', ENV.to_h.merge('PANGEA_NO_COLOR' => '1'))
      described_class.override_enabled(nil)
      expect(described_class.enabled?).to be false
    end

    it 'returns false when TERM=dumb' do
      stub_const('ENV', ENV.to_h.merge('TERM' => 'dumb'))
      described_class.override_enabled(nil)
      expect(described_class.enabled?).to be false
    end
  end

  describe '.color' do
    it 'emits ANSI sequence when enabled' do
      described_class.override_enabled(true)
      out = described_class.color(:error, 'bad')
      expect(out).to start_with("\e[38;2;191;97;106m") # nord11
      expect(out).to end_with("\e[0m")
      expect(out).to include('bad')
    end

    it 'returns plain string when disabled' do
      described_class.override_enabled(false)
      expect(described_class.color(:error, 'bad')).to eq('bad')
    end

    it 'returns plain string for unknown role' do
      described_class.override_enabled(true)
      expect(described_class.color(:nonexistent, 'x')).to eq('x')
    end

    it 'green (nord14) for :success/:create' do
      described_class.override_enabled(true)
      expect(described_class.color(:success, 'ok'))
        .to start_with("\e[38;2;163;190;140m")
      expect(described_class.color(:create, '+'))
        .to start_with("\e[38;2;163;190;140m")
    end

    it 'yellow (nord13) for :warning' do
      described_class.override_enabled(true)
      expect(described_class.color(:warning, 'watch'))
        .to start_with("\e[38;2;235;203;139m")
    end

    it 'cyan (nord8) for :info/:update' do
      described_class.override_enabled(true)
      expect(described_class.color(:info, 'x'))
        .to start_with("\e[38;2;136;192;208m")
      expect(described_class.color(:update, '~'))
        .to start_with("\e[38;2;136;192;208m")
    end

    it 'muted (nord3) for :label/:deprecation' do
      described_class.override_enabled(true)
      expect(described_class.color(:label, '[pangea]'))
        .to start_with("\e[38;2;76;86;106m")
      expect(described_class.color(:deprecation, '(suppressed)'))
        .to start_with("\e[38;2;76;86;106m")
    end
  end

  describe '.bold / .dim' do
    it 'wraps with bold code when enabled' do
      described_class.override_enabled(true)
      expect(described_class.bold('x')).to eq("\e[1mx\e[0m")
    end

    it 'returns plain when disabled' do
      described_class.override_enabled(false)
      expect(described_class.bold('x')).to eq('x')
    end
  end

  describe '.action_glyph' do
    before { described_class.override_enabled(true) }

    it 'create is green +' do
      out = described_class.action_glyph('create')
      expect(out).to include('+')
      expect(out).to start_with("\e[38;2;163;190;140m")
    end

    it 'update is cyan ~' do
      out = described_class.action_glyph('update')
      expect(out).to include('~')
      expect(out).to start_with("\e[38;2;136;192;208m")
    end

    it 'delete is red -' do
      out = described_class.action_glyph('delete')
      expect(out).to include('-')
      expect(out).to start_with("\e[38;2;191;97;106m")
    end

    it 'replace is yellow ±' do
      out = described_class.action_glyph('replace')
      expect(out).to include('±')
      expect(out).to start_with("\e[38;2;235;203;139m")
    end

    it 'no-op is muted =' do
      out = described_class.action_glyph('no-op')
      expect(out).to include('=')
      expect(out).to start_with("\e[38;2;76;86;106m")
    end
  end

  describe '.marker / MARKER' do
    it 'uses a snowflake per blackmatter convention' do
      expect(described_class::MARKER).to eq('❄')
    end

    it 'returns the snowflake colored by level when enabled' do
      described_class.override_enabled(true)
      out = described_class.marker(level: :success)
      expect(out).to include('❄')
      expect(out).to include("\e[38;2;163;190;140m") # green
    end

    it 'returns plain snowflake when disabled' do
      described_class.override_enabled(false)
      expect(described_class.marker).to eq('❄')
    end
  end

  describe '.log' do
    it 'emits snowflake marker + colored body' do
      described_class.override_enabled(true)
      io = StringIO.new
      described_class.log('hello', level: :success, io: io)
      out = io.string
      expect(out).to include('❄')
      expect(out).to include('hello')
      expect(out).to include("\e[38;2;163;190;140m") # green
    end

    it 'does not use the square-bracket [pangea] label' do
      described_class.override_enabled(true)
      io = StringIO.new
      described_class.log('hello', io: io)
      expect(io.string).not_to include('[pangea]')
    end
  end

  describe '.structured_log' do
    it 'concatenates role-tagged parts separated by spaces after the marker' do
      described_class.override_enabled(true)
      io = StringIO.new
      described_class.structured_log(
        [:info, 'Synthesizing'],
        [:path, '/tmp/x.rb'],
        io: io,
      )
      out = io.string
      expect(out).to start_with(described_class.marker(level: :info))
      expect(out).to include('Synthesizing')
      expect(out).to include('/tmp/x.rb')
    end
  end

  describe '.section' do
    it 'emits snowflake + title + divider' do
      described_class.override_enabled(true)
      io = StringIO.new
      described_class.section('plan', io: io, width: 20)
      out = io.string
      expect(out).to include('❄')
      expect(out).to include('plan')
      expect(out).to include('─')
    end
  end

  describe '.count' do
    it 'mutes zero counts' do
      described_class.override_enabled(true)
      out = described_class.count(0)
      expect(out).to include('0')
      expect(out).to start_with("\e[38;2;76;86;106m") # muted
    end

    it 'highlights non-zero counts' do
      described_class.override_enabled(true)
      out = described_class.count(5)
      expect(out).to include('5')
      expect(out).to start_with("\e[38;2;235;203;139m") # yellow
    end
  end
end
