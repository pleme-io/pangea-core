# frozen_string_literal: true

require 'spec_helper'
require 'fileutils'
require 'tmpdir'
require 'pangea/cli/cascade'

RSpec.describe Pangea::CLI::Cascade do
  # Builds a minimal constellation on disk with pangea.yml + .rb template
  # files. Doesn't synthesize anything — the specs stub Operations to
  # capture the call order without touching tofu.
  def build_constellation(decls)
    root = Dir.mktmpdir('cascade_')
    paths = {}
    decls.each do |name, asks|
      dir = File.join(root, name)
      FileUtils.mkdir_p(dir)
      paths[name] = dir

      yml = { 'workspace' => name, 'kind' => name.sub(/^platform-/, '') }
      yml['reactivity'] = { 'asks' => asks } unless asks.empty?
      File.write(File.join(dir, 'pangea.yml'), yml.to_yaml)
      File.write(File.join(dir, "#{name.tr('-', '_')}.rb"), "# template for #{name}\n")
    end
    [root, paths]
  end

  around do |ex|
    original = ENV['PANGEA_NO_CASCADE']
    ENV.delete('PANGEA_NO_CASCADE')
    ex.run
  ensure
    ENV['PANGEA_NO_CASCADE'] = original
  end

  describe '.for_template' do
    it 'returns nil for an isolated template (no sibling workspaces)' do
      Dir.mktmpdir do |solo|
        File.write(File.join(solo, 'pangea.yml'), { 'workspace' => 'solo' }.to_yaml)
        template = File.join(solo, 'solo.rb')
        File.write(template, "# solo\n")
        expect(described_class.for_template(template)).to be_nil
      end
    end

    it 'returns nil when the seed has no reactive neighbors' do
      root, paths = build_constellation(
        'platform-iam' => [],
        'platform-state' => [],
      )
      template = File.join(paths['platform-iam'], 'platform_iam.rb')
      # Two workspaces exist in the constellation but neither references
      # the other — cascade should not fire.
      expect(described_class.for_template(template)).to be_nil
    ensure
      FileUtils.rm_rf(root)
    end

    it 'returns nil when PANGEA_NO_CASCADE=1 (escape hatch)' do
      ENV['PANGEA_NO_CASCADE'] = '1'
      root, paths = build_constellation(
        'platform-vpc' => [],
        'platform-dns' => [
          { 'layer' => 'vpc', 'workspace' => 'platform-vpc', 'output' => 'vpc_id', 'bind' => 'vpc_id' },
        ],
      )
      template = File.join(paths['platform-dns'], 'platform_dns.rb')
      expect(described_class.for_template(template)).to be_nil
    ensure
      FileUtils.rm_rf(root)
    end

    it 'returns a Cascade when the seed has reactive neighbors' do
      root, paths = build_constellation(
        'platform-vpc' => [],
        'platform-dns' => [
          { 'layer' => 'vpc', 'workspace' => 'platform-vpc', 'output' => 'vpc_id', 'bind' => 'vpc_id' },
        ],
      )
      template = File.join(paths['platform-dns'], 'platform_dns.rb')
      cascade = described_class.for_template(template)
      expect(cascade).to be_a(described_class)
      expect(cascade.seed_name).to eq('platform-dns')
      expect(cascade.ordered_names).to eq(%w[platform-vpc platform-dns])
    ensure
      FileUtils.rm_rf(root)
    end
  end

  describe 'execution order' do
    let(:constellation) do
      build_constellation(
        'platform-vpc' => [],
        'platform-dns' => [
          { 'layer' => 'vpc', 'workspace' => 'platform-vpc', 'output' => 'vpc_id', 'bind' => 'vpc_id' },
        ],
        'platform-cache' => [
          { 'layer' => 'vpc', 'workspace' => 'platform-vpc', 'output' => 'vpc_id', 'bind' => 'vpc_id' },
          { 'layer' => 'dns', 'workspace' => 'platform-dns', 'output' => 'zone_id', 'bind' => 'zone_id' },
        ],
      )
    end

    after { FileUtils.rm_rf(@root) if @root }

    # Capture calls to Operations#plan/apply/destroy without actually
    # running tofu. Returns the names in the order they were invoked.
    def capture_order(cascade, method)
      call_order = []
      allow_any_instance_of(Pangea::CLI::Operations).to receive(method) do |ops|
        call_order << File.basename(ops.config.template_dir)
      end
      cascade.public_send(method)
      call_order
    end

    it 'plan runs in topological order (upstream first)' do
      @root, paths = constellation
      cascade = described_class.for_template(
        File.join(paths['platform-cache'], 'platform_cache.rb'),
      )
      order = capture_order(cascade, :plan)
      expect(order).to eq(%w[platform-vpc platform-dns platform-cache])
    end

    it 'apply runs in topological order (upstream first)' do
      @root, paths = constellation
      cascade = described_class.for_template(
        File.join(paths['platform-cache'], 'platform_cache.rb'),
      )
      order = capture_order(cascade, :apply)
      expect(order).to eq(%w[platform-vpc platform-dns platform-cache])
    end

    it 'destroy runs in REVERSE topological order (leaves first)' do
      @root, paths = constellation
      cascade = described_class.for_template(
        File.join(paths['platform-cache'], 'platform_cache.rb'),
      )
      order = capture_order(cascade, :destroy)
      expect(order).to eq(%w[platform-cache platform-dns platform-vpc])
    end

    it 'plan continues past a failing stage (warning, not abort)' do
      @root, paths = constellation
      cascade = described_class.for_template(
        File.join(paths['platform-cache'], 'platform_cache.rb'),
      )
      call_order = []
      allow_any_instance_of(Pangea::CLI::Operations).to receive(:plan) do |ops|
        name = File.basename(ops.config.template_dir)
        call_order << name
        raise 'boom' if name == 'platform-dns'
      end
      # silence stderr during this test
      allow($stderr).to receive(:puts)
      cascade.plan
      expect(call_order).to eq(%w[platform-vpc platform-dns platform-cache])
    end

    it 'apply aborts the cascade on the first failure' do
      @root, paths = constellation
      cascade = described_class.for_template(
        File.join(paths['platform-cache'], 'platform_cache.rb'),
      )
      call_order = []
      allow_any_instance_of(Pangea::CLI::Operations).to receive(:apply) do |ops|
        name = File.basename(ops.config.template_dir)
        call_order << name
        raise 'boom' if name == 'platform-vpc'
      end
      allow($stderr).to receive(:puts)
      cascade.apply
      expect(call_order).to eq(%w[platform-vpc])
    end
  end

  describe 'recap aggregation' do
    let(:constellation) do
      build_constellation(
        'platform-vpc' => [],
        'platform-dns' => [
          { 'layer' => 'vpc', 'workspace' => 'platform-vpc', 'output' => 'vpc_id', 'bind' => 'vpc_id' },
        ],
      )
    end

    after { FileUtils.rm_rf(@root) if @root }

    it 'collects one StageOutcome per stage' do
      @root, paths = constellation
      cascade = described_class.for_template(
        File.join(paths['platform-dns'], 'platform_dns.rb'),
      )
      allow_any_instance_of(Pangea::CLI::Operations).to receive(:plan) do |ops|
        name = File.basename(ops.config.template_dir)
        ops.instance_variable_set(:@last_outcome, Pangea::CLI::Operations::StageOutcome.new(
          operation: 'plan', workspace: name, success: true,
          added: name == 'platform-vpc' ? 3 : 1,
          changed: 0, removed: 0,
          transient_errors: 0, dropped_warnings: 0, error: nil,
        ))
      end
      allow($stderr).to receive(:puts)

      cascade.plan

      expect(cascade.outcomes.size).to eq(2)
      expect(cascade.outcomes.map(&:workspace)).to eq(%w[platform-vpc platform-dns])
      expect(cascade.outcomes.sum(&:total_changes)).to eq(4)
    end

    it 'records a synthetic failed outcome when a stage raises before running tofu' do
      @root, paths = constellation
      cascade = described_class.for_template(
        File.join(paths['platform-dns'], 'platform_dns.rb'),
      )
      allow_any_instance_of(Pangea::CLI::Operations).to receive(:plan) do |ops|
        name = File.basename(ops.config.template_dir)
        raise 'boom' if name == 'platform-dns'

        ops.instance_variable_set(:@last_outcome, Pangea::CLI::Operations::StageOutcome.new(
          operation: 'plan', workspace: name, success: true,
          added: 0, changed: 0, removed: 0,
          transient_errors: 0, dropped_warnings: 0, error: nil,
        ))
      end
      allow($stderr).to receive(:puts)

      cascade.plan

      expect(cascade.outcomes.size).to eq(2)
      failed = cascade.outcomes.last
      expect(failed.workspace).to eq('platform-dns')
      expect(failed.success).to be(false)
      expect(failed.error).to eq('boom')
    end

    it 'renders a recap section to stderr' do
      @root, paths = constellation
      cascade = described_class.for_template(
        File.join(paths['platform-dns'], 'platform_dns.rb'),
      )
      allow_any_instance_of(Pangea::CLI::Operations).to receive(:plan) do |ops|
        ops.instance_variable_set(:@last_outcome, Pangea::CLI::Operations::StageOutcome.new(
          operation: 'plan', workspace: File.basename(ops.config.template_dir), success: true,
          added: 2, changed: 1, removed: 0,
          transient_errors: 0, dropped_warnings: 0, error: nil,
        ))
      end
      lines = []
      allow($stderr).to receive(:puts) { |line| lines << line }

      cascade.plan

      recap = lines.join("\n")
      expect(recap).to match(/cascade recap/)
      expect(recap).to match(/platform-vpc/)
      expect(recap).to match(/platform-dns/)
      expect(recap).to match(/Total:/)
    end
  end

  describe 'cascade depth' do
    let(:wide_constellation) do
      # vpc (root) ← dns ← cache ← packer
      build_constellation(
        'platform-vpc' => [],
        'platform-dns' => [
          { 'layer' => 'vpc', 'workspace' => 'platform-vpc', 'output' => 'vpc_id', 'bind' => 'vpc_id' },
        ],
        'platform-cache' => [
          { 'layer' => 'dns', 'workspace' => 'platform-dns', 'output' => 'zone_id', 'bind' => 'zone_id' },
        ],
        'platform-packer' => [
          { 'layer' => 'cache', 'workspace' => 'platform-cache', 'output' => 'cache_endpoint', 'bind' => 'cache_endpoint' },
        ],
      )
    end

    after { FileUtils.rm_rf(@root) if @root }

    it 'explicit max_depth argument limits the cascade' do
      @root, paths = wide_constellation
      cascade = described_class.for_template(
        File.join(paths['platform-dns'], 'platform_dns.rb'),
        max_depth: 1,
      )
      # From dns at depth 1: vpc (upstream) + cache (downstream). Packer is
      # 2 hops away (dns → cache → packer) so excluded.
      expect(cascade.ordered_names).to contain_exactly(
        'platform-vpc', 'platform-dns', 'platform-cache'
      )
      expect(cascade.max_depth).to eq(1)
    end

    it 'depth 0 collapses to single-workspace (returns nil)' do
      @root, paths = wide_constellation
      cascade = described_class.for_template(
        File.join(paths['platform-dns'], 'platform_dns.rb'),
        max_depth: 0,
      )
      expect(cascade).to be_nil
    end

    it 'resolves default_depth from workspace pangea.yml when CLI omits it' do
      @root, paths = wide_constellation
      # Inject cascade.default_depth into the seed's pangea.yml
      yml = YAML.safe_load(File.read(File.join(paths['platform-dns'], 'pangea.yml')))
      yml['cascade'] = { 'default_depth' => 1 }
      File.write(File.join(paths['platform-dns'], 'pangea.yml'), yml.to_yaml)

      cascade = described_class.for_template(
        File.join(paths['platform-dns'], 'platform_dns.rb'),
      )
      expect(cascade.max_depth).to eq(1)
      expect(cascade.ordered_names).to contain_exactly(
        'platform-vpc', 'platform-dns', 'platform-cache'
      )
    end

    it 'PANGEA_CASCADE_DEPTH env var overrides yml default but is overridden by explicit arg' do
      @root, paths = wide_constellation
      yml = YAML.safe_load(File.read(File.join(paths['platform-dns'], 'pangea.yml')))
      yml['cascade'] = { 'default_depth' => 99 }
      File.write(File.join(paths['platform-dns'], 'pangea.yml'), yml.to_yaml)

      ENV['PANGEA_CASCADE_DEPTH'] = '1'
      cascade_env = described_class.for_template(
        File.join(paths['platform-dns'], 'platform_dns.rb'),
      )
      expect(cascade_env.max_depth).to eq(1)

      cascade_explicit = described_class.for_template(
        File.join(paths['platform-dns'], 'platform_dns.rb'),
        max_depth: 2,
      )
      expect(cascade_explicit.max_depth).to eq(2)
    ensure
      ENV.delete('PANGEA_CASCADE_DEPTH')
    end

    it 'unlimited depth (nil) visits the full transitive closure' do
      @root, paths = wide_constellation
      cascade = described_class.for_template(
        File.join(paths['platform-packer'], 'platform_packer.rb'),
      )
      expect(cascade.ordered_names).to contain_exactly(
        'platform-vpc', 'platform-dns', 'platform-cache', 'platform-packer'
      )
      expect(cascade.max_depth).to be_nil
    end
  end

  describe 'cascade pre/post actions' do
    let(:constellation_with_actions) do
      build_constellation(
        'platform-vpc' => [],
        'platform-dns' => [
          { 'layer' => 'vpc', 'workspace' => 'platform-vpc', 'output' => 'vpc_id', 'bind' => 'vpc_id' },
        ],
      ).tap do |root, paths|
        yml = YAML.safe_load(File.read(File.join(paths['platform-dns'], 'pangea.yml')))
        yml['cascade'] = {
          'pre_actions' => %w[synth],
          'post_actions' => %w[output],
        }
        File.write(File.join(paths['platform-dns'], 'pangea.yml'), yml.to_yaml)
      end
    end

    after { FileUtils.rm_rf(@root) if @root }

    it 'invokes pre_actions BEFORE primary command and post_actions AFTER' do
      @root, paths = constellation_with_actions
      cascade = described_class.for_template(
        File.join(paths['platform-dns'], 'platform_dns.rb'),
      )

      call_order = []
      allow_any_instance_of(Pangea::CLI::Operations).to receive(:synth) do |ops, **|
        call_order << ['synth', File.basename(ops.config.template_dir)]
      end
      allow_any_instance_of(Pangea::CLI::Operations).to receive(:output) do |ops|
        call_order << ['output', File.basename(ops.config.template_dir)]
      end
      allow_any_instance_of(Pangea::CLI::Operations).to receive(:plan) do |ops|
        call_order << ['plan', File.basename(ops.config.template_dir)]
      end
      allow($stderr).to receive(:puts)

      cascade.plan

      # platform-vpc has no cascade actions declared → just plan.
      # platform-dns has pre=synth, post=output → synth, plan, output.
      dns_calls = call_order.select { |_, ws| ws == 'platform-dns' }.map(&:first)
      expect(dns_calls).to eq(%w[synth plan output])
      vpc_calls = call_order.select { |_, ws| ws == 'platform-vpc' }.map(&:first)
      expect(vpc_calls).to eq(%w[plan])
    end

    # Conflict rejection is structurally enforced at Workspace.load time
    # (see reactivity_spec — raises InvalidActionError for plan/apply/
    # destroy/deploy). The run_actions skip is belt-and-suspenders only;
    # no separate test needed here.
  end
end
