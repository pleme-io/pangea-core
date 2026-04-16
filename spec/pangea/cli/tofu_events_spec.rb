# frozen_string_literal: true

require 'spec_helper'
require 'pangea/cli'

RSpec.describe Pangea::CLI::TofuEvents do
  describe Pangea::CLI::TofuEvents::Event do
    it 'exposes type/level/message' do
      event = described_class.new(
        'type' => 'log', '@level' => 'info', '@message' => 'hello'
      )
      expect(event.type).to eq('log')
      expect(event.level).to eq('info')
      expect(event.message).to eq('hello')
    end

    it 'detects transient NoSuchEntity as retryable' do
      event = described_class.new(
        'type' => 'diagnostic',
        'diagnostic' => {
          'severity' => 'error',
          'summary'  => 'putting IAM Role Policy',
          'detail'   => 'NoSuchEntity: The role cannot be found',
        }
      )
      expect(event.transient_error?).to be true
    end

    it 'detects Throttling as transient' do
      event = described_class.new(
        'type' => 'diagnostic',
        'diagnostic' => {
          'severity' => 'error',
          'summary'  => 'Throttling: Rate exceeded',
          'detail'   => '',
        }
      )
      expect(event.transient_error?).to be true
    end

    it 'does not mark random errors as transient' do
      event = described_class.new(
        'type' => 'diagnostic',
        'diagnostic' => {
          'severity' => 'error',
          'summary'  => 'Invalid CIDR block',
          'detail'   => 'CIDR 10.0.0.0/99 is not valid',
        }
      )
      expect(event.transient_error?).to be false
    end

    it 'drops inline_policy deprecation warnings' do
      event = described_class.new(
        'type' => 'diagnostic',
        'diagnostic' => {
          'severity' => 'warning',
          'summary'  => 'inline_policy is deprecated',
          'detail'   => '',
        }
      )
      expect(event.dropped_warning?).to be true
    end

    it 'does not drop non-deprecation warnings' do
      event = described_class.new(
        'type' => 'diagnostic',
        'diagnostic' => {
          'severity' => 'warning',
          'summary'  => 'Value for undeclared variable',
          'detail'   => '',
        }
      )
      expect(event.dropped_warning?).to be false
    end

    it 'exposes resource address from planned_change' do
      event = described_class.new(
        'type'   => 'planned_change',
        'change' => {
          'action'   => 'create',
          'resource' => { 'addr' => 'aws_iam_role.example' },
        }
      )
      expect(event.resource_address).to eq('aws_iam_role.example')
    end

    it 'exposes resource address from apply hook' do
      event = described_class.new(
        'type' => 'apply_start',
        'hook' => { 'resource' => { 'addr' => 'aws_iam_role.example' } }
      )
      expect(event.resource_address).to eq('aws_iam_role.example')
    end
  end

  describe Pangea::CLI::TofuEvents::Collector do
    it 'accumulates events' do
      c = described_class.new
      c.consume(Pangea::CLI::TofuEvents::Event.new('type' => 'log'))
      c.consume(Pangea::CLI::TofuEvents::Event.new('type' => 'log'))
      expect(c.events.size).to eq(2)
    end

    it 'captures plan summary (operation inside changes hash — real OpenTofu format)' do
      c = described_class.new
      c.consume(Pangea::CLI::TofuEvents::Event.new(
        'type'    => 'change_summary',
        'changes' => {
          'add' => 3, 'change' => 1, 'remove' => 0, 'operation' => 'plan'
        }
      ))
      expect(c.plan_summary).to include('add' => 3)
      expect(c.summary_line).to eq('Plan: 3 to add, 1 to change, 0 to destroy')
    end

    it 'reports Plan: No changes. when all zero' do
      c = described_class.new
      c.consume(Pangea::CLI::TofuEvents::Event.new(
        'type'    => 'change_summary',
        'changes' => {
          'add' => 0, 'change' => 0, 'remove' => 0, 'operation' => 'plan'
        }
      ))
      expect(c.summary_line).to eq('Plan: No changes.')
    end

    it 'captures apply summary separately from plan' do
      c = described_class.new
      c.consume(Pangea::CLI::TofuEvents::Event.new(
        'type'    => 'change_summary',
        'changes' => {
          'add' => 5, 'change' => 0, 'remove' => 0, 'operation' => 'apply'
        }
      ))
      expect(c.apply_summary).to include('add' => 5)
      expect(c.summary_line).to eq('Apply: 5 added, 0 changed, 0 destroyed')
    end

    it 'collects transient errors' do
      c = described_class.new
      c.consume(Pangea::CLI::TofuEvents::Event.new(
        'type' => 'diagnostic',
        'diagnostic' => {
          'severity' => 'error',
          'summary'  => 'Throttling',
          'detail'   => 'Rate exceeded',
        }
      ))
      expect(c.any_transient_errors?).to be true
      expect(c.transient_errors.size).to eq(1)
    end

    it 'tracks dropped warnings' do
      c = described_class.new
      c.consume(Pangea::CLI::TofuEvents::Event.new(
        'type' => 'diagnostic',
        'diagnostic' => {
          'severity' => 'warning',
          'summary'  => 'inline_policy is deprecated',
        }
      ))
      expect(c.dropped_warnings.size).to eq(1)
    end
  end

  describe '.render_human' do
    it 'renders planned create as +' do
      event = Pangea::CLI::TofuEvents::Event.new(
        'type'   => 'planned_change',
        'change' => {
          'action'   => 'create',
          'resource' => { 'addr' => 'aws_iam_role.foo' },
        }
      )
      expect(described_class.render_human(event)).to eq('  + aws_iam_role.foo')
    end

    it 'renders planned update as ~' do
      event = Pangea::CLI::TofuEvents::Event.new(
        'type'   => 'planned_change',
        'change' => {
          'action'   => 'update',
          'resource' => { 'addr' => 'aws_iam_role.foo' },
        }
      )
      expect(described_class.render_human(event)).to eq('  ~ aws_iam_role.foo')
    end

    it 'renders apply_complete as check' do
      event = Pangea::CLI::TofuEvents::Event.new(
        'type' => 'apply_complete',
        'hook' => { 'resource' => { 'addr' => 'aws_iam_role.foo' } }
      )
      expect(described_class.render_human(event)).to include('aws_iam_role.foo')
    end

    it 'returns nil for dropped warnings' do
      event = Pangea::CLI::TofuEvents::Event.new(
        'type' => 'diagnostic',
        'diagnostic' => {
          'severity' => 'warning',
          'summary'  => 'inline_policy is deprecated',
        }
      )
      expect(described_class.render_human(event)).to be_nil
    end

    it 'returns nil for change_summary (rendered separately)' do
      event = Pangea::CLI::TofuEvents::Event.new(
        'type'    => 'change_summary',
        'changes' => {
          'add' => 1, 'change' => 0, 'remove' => 0, 'operation' => 'plan'
        }
      )
      expect(described_class.render_human(event)).to be_nil
    end

    it 'renders non-dropped warnings with severity prefix' do
      event = Pangea::CLI::TofuEvents::Event.new(
        'type' => 'diagnostic',
        'diagnostic' => {
          'severity' => 'warning',
          'summary'  => 'Value for undeclared variable',
          'detail'   => 'The root module does not declare variable foo',
        }
      )
      out = described_class.render_human(event)
      expect(out).to include('[WARNING]')
      expect(out).to include('Value for undeclared variable')
      expect(out).to include('The root module does not declare variable foo')
    end
  end

  describe '.parse_line' do
    it 'parses a valid JSON line into an Event' do
      line = '{"type":"log","@level":"info","@message":"hello"}'
      event = described_class.parse_line(line)
      expect(event).to be_a(Pangea::CLI::TofuEvents::Event)
      expect(event.message).to eq('hello')
    end

    it 'returns nil for non-JSON input (init prelude, etc.)' do
      expect(described_class.parse_line('Initializing the backend...')).to be_nil
      expect(described_class.parse_line('')).to be_nil
      expect(described_class.parse_line(nil)).to be_nil
    end
  end
end
