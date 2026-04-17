# frozen_string_literal: true

require 'spec_helper'
require 'fileutils'
require 'tmpdir'
require 'pangea/cli/reactivity'

RSpec.describe Pangea::CLI::Reactivity do
  # Builds a constellation of workspace dirs inside a tmp root. `decls` is
  # a Hash<workspace_name, Array<{layer,workspace,output,bind}>>. Returns
  # [root_dir_path, Hash<name, dir_path>] for use in specs.
  def build_constellation(decls)
    root = Dir.mktmpdir('constellation_')
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

  describe described_class::Ask do
    it 'constructs from hash with all four fields' do
      ask = described_class.from_h(
        'layer' => 'vpc',
        'workspace' => 'platform-vpc',
        'output' => 'vpc_id',
        'bind' => 'vpc_id',
      )
      expect(ask.layer).to eq('vpc')
      expect(ask.workspace).to eq('platform-vpc')
      expect(ask.output).to eq('vpc_id')
      expect(ask.bind).to eq('vpc_id')
    end

    it 'raises KeyError when a required field is missing' do
      expect {
        described_class.from_h('layer' => 'vpc', 'workspace' => 'platform-vpc')
      }.to raise_error(KeyError)
    end
  end

  describe described_class::Workspace do
    it 'loads a workspace with a reactivity block' do
      root, paths = build_constellation(
        'platform-dns' => [
          { 'layer' => 'vpc', 'workspace' => 'platform-vpc', 'output' => 'vpc_id', 'bind' => 'vpc_id' },
        ],
      )
      ws = described_class.load(paths['platform-dns'])
      expect(ws.name).to eq('platform-dns')
      expect(ws).to be_reactive
      expect(ws.asks.size).to eq(1)
      expect(ws.asks.first.output).to eq('vpc_id')
    ensure
      FileUtils.rm_rf(root)
    end

    it 'loads a workspace with no reactivity block as non-reactive' do
      root, paths = build_constellation('platform-iam' => [])
      ws = described_class.load(paths['platform-iam'])
      expect(ws).not_to be_reactive
      expect(ws.asks).to be_empty
    ensure
      FileUtils.rm_rf(root)
    end

    it 'returns nil when pangea.yml is missing' do
      Dir.mktmpdir do |dir|
        expect(described_class.load(dir)).to be_nil
      end
    end

    it 'returns unique upstream workspace names' do
      root, paths = build_constellation(
        'platform-cache' => [
          { 'layer' => 'vpc', 'workspace' => 'platform-vpc', 'output' => 'vpc_id', 'bind' => 'vpc_id' },
          { 'layer' => 'vpc', 'workspace' => 'platform-vpc', 'output' => 'subnet_ids', 'bind' => 'subnet_ids' },
          { 'layer' => 'dns', 'workspace' => 'platform-dns', 'output' => 'zone_id', 'bind' => 'zone_id' },
        ],
      )
      ws = described_class.load(paths['platform-cache'])
      expect(ws.upstream_names).to contain_exactly('platform-vpc', 'platform-dns')
    ensure
      FileUtils.rm_rf(root)
    end
  end

  describe described_class::Graph do
    let(:constellation) do
      # Models the real pangea-architectures constellation:
      #   iam, state, vpc  -> root (no asks)
      #   dns              -> asks vpc
      #   cache            -> asks vpc, dns
      #   packer           -> asks vpc, iam, cache
      #   builder-fleet    -> asks vpc, dns, cache
      build_constellation(
        'platform-iam' => [],
        'platform-state' => [],
        'platform-vpc' => [],
        'platform-dns' => [
          { 'layer' => 'vpc', 'workspace' => 'platform-vpc', 'output' => 'vpc_id', 'bind' => 'vpc_id' },
        ],
        'platform-cache' => [
          { 'layer' => 'vpc', 'workspace' => 'platform-vpc', 'output' => 'vpc_id', 'bind' => 'vpc_id' },
          { 'layer' => 'vpc', 'workspace' => 'platform-vpc', 'output' => 'subnet_ids', 'bind' => 'subnet_ids' },
          { 'layer' => 'dns', 'workspace' => 'platform-dns', 'output' => 'zone_id', 'bind' => 'zone_id' },
        ],
        'platform-packer' => [
          { 'layer' => 'vpc', 'workspace' => 'platform-vpc', 'output' => 'vpc_id', 'bind' => 'vpc_id' },
          { 'layer' => 'iam', 'workspace' => 'platform-iam', 'output' => 'role_arn', 'bind' => 'role_arn' },
          { 'layer' => 'cache', 'workspace' => 'platform-cache', 'output' => 'cache_endpoint', 'bind' => 'cache_endpoint' },
        ],
        'platform-builder-fleet' => [
          { 'layer' => 'vpc', 'workspace' => 'platform-vpc', 'output' => 'vpc_id', 'bind' => 'vpc_id' },
          { 'layer' => 'dns', 'workspace' => 'platform-dns', 'output' => 'zone_id', 'bind' => 'zone_id' },
          { 'layer' => 'cache', 'workspace' => 'platform-cache', 'output' => 'cache_endpoint', 'bind' => 'cache_endpoint' },
        ],
      )
    end

    after do
      FileUtils.rm_rf(@root) if @root
    end

    def scan
      @root, _ = constellation
      described_class.scan(@root)
    end

    it 'discovers every workspace directory with a pangea.yml' do
      g = scan
      expect(g.names).to contain_exactly(
        'platform-iam', 'platform-state', 'platform-vpc',
        'platform-dns', 'platform-cache', 'platform-packer',
        'platform-builder-fleet'
      )
    end

    it 'returns an empty graph for a missing root' do
      g = described_class.scan('/nonexistent/path')
      expect(g.names).to be_empty
    end

    it 'resolves direct upstream workspaces from a name' do
      g = scan
      expect(g.upstream_of('platform-cache')).to contain_exactly('platform-vpc', 'platform-dns')
      expect(g.upstream_of('platform-vpc')).to be_empty
    end

    it 'resolves direct downstream workspaces from a name' do
      g = scan
      expect(g.downstream_of('platform-vpc')).to contain_exactly(
        'platform-dns', 'platform-cache', 'platform-packer', 'platform-builder-fleet'
      )
      expect(g.downstream_of('platform-builder-fleet')).to be_empty
    end

    it 'cascade_set from vpc transitively reaches every reactive workspace' do
      g = scan
      # Bidirectional closure: packer also asks iam, so iam is pulled in
      # via packer's upstream — which is correct. A cascade is reachability
      # through the reactive edge set in both directions.
      expect(g.cascade_set('platform-vpc')).to contain_exactly(
        'platform-vpc', 'platform-dns', 'platform-cache',
        'platform-packer', 'platform-builder-fleet', 'platform-iam'
      )
    end

    it 'cascade_set from dns includes upstream (vpc) AND downstream (cache, builder-fleet, packer via cache)' do
      g = scan
      set = g.cascade_set('platform-dns')
      expect(set).to include('platform-dns', 'platform-vpc', 'platform-cache', 'platform-builder-fleet')
      # packer reaches dns only through cache (cache -> dns upstream, cache -> packer downstream)
      expect(set).to include('platform-packer')
    end

    it 'cascade_set from an isolated workspace returns just itself' do
      g = scan
      expect(g.cascade_set('platform-state')).to contain_exactly('platform-state')
    end

    it 'raises MissingWorkspaceError for unknown name' do
      g = scan
      expect { g.cascade_set('platform-bogus') }.to raise_error(
        Pangea::CLI::Reactivity::MissingWorkspaceError
      )
    end

    it 'topo_sort orders upstream before downstream' do
      g = scan
      all = g.cascade_set('platform-vpc')
      ordered = g.topo_sort(all)

      vpc_idx = ordered.index('platform-vpc')
      dns_idx = ordered.index('platform-dns')
      cache_idx = ordered.index('platform-cache')
      fleet_idx = ordered.index('platform-builder-fleet')
      packer_idx = ordered.index('platform-packer')

      # vpc before everyone
      expect(vpc_idx).to be < dns_idx
      expect(vpc_idx).to be < cache_idx
      # dns before cache (cache asks dns)
      expect(dns_idx).to be < cache_idx
      # cache before fleet + packer
      expect(cache_idx).to be < fleet_idx
      expect(cache_idx).to be < packer_idx
    end

    it 'topo_sort is deterministic — ties break alphabetically' do
      g = scan
      subset = Set.new(['platform-iam', 'platform-state', 'platform-vpc'])
      ordered = g.topo_sort(subset)
      # All three are roots; alphabetical order.
      expect(ordered).to eq(%w[platform-iam platform-state platform-vpc])
    end

    it 'topo_sort raises CycleError when a cycle exists' do
      # Construct a tiny cycle: A asks B, B asks A.
      @root, _paths = build_constellation(
        'ws-a' => [{ 'layer' => 'b', 'workspace' => 'ws-b', 'output' => 'x', 'bind' => 'x' }],
        'ws-b' => [{ 'layer' => 'a', 'workspace' => 'ws-a', 'output' => 'y', 'bind' => 'y' }],
      )
      g = described_class.scan(@root)
      expect { g.topo_sort(Set.new(%w[ws-a ws-b])) }.to raise_error(
        Pangea::CLI::Reactivity::CycleError, /ws-a, ws-b/
      )
    end

    it 'workspaces_root_for walks up from a template file to the constellation root' do
      @root, paths = constellation
      template = File.join(paths['platform-cache'], 'platform_cache.rb')
      found = described_class.workspaces_root_for(template)
      expect(File.realpath(found)).to eq(File.realpath(@root))
    end

    it 'workspaces_root_for returns nil for an isolated template' do
      Dir.mktmpdir do |solo|
        File.write(File.join(solo, 'pangea.yml'), { 'workspace' => 'solo' }.to_yaml)
        template = File.join(solo, 'solo.rb')
        File.write(template, "# solo\n")
        expect(described_class.workspaces_root_for(template)).to be_nil
      end
    end

    describe 'cascade_set with max_depth' do
      it 'depth 0 returns just the seed' do
        @root, _ = constellation
        g = described_class.scan(@root)
        expect(g.cascade_set('platform-vpc', max_depth: 0)).to contain_exactly('platform-vpc')
      end

      it 'depth 1 returns seed + direct neighbors only' do
        @root, _ = constellation
        g = described_class.scan(@root)
        # platform-dns asks VPC; platform-cache asks VPC too.
        # Direct neighbors of VPC: dns, cache, packer, builder-fleet.
        set = g.cascade_set('platform-vpc', max_depth: 1)
        expect(set).to contain_exactly(
          'platform-vpc', 'platform-dns', 'platform-cache',
          'platform-packer', 'platform-builder-fleet'
        )
        # iam is only reachable via packer → 2 hops. Excluded at depth 1.
        expect(set).not_to include('platform-iam')
      end

      it 'unlimited depth (nil) matches original behavior' do
        @root, _ = constellation
        g = described_class.scan(@root)
        unlimited = g.cascade_set('platform-vpc', max_depth: nil)
        unbounded = g.cascade_set('platform-vpc')
        expect(unlimited).to eq(unbounded)
      end

      it 'depth 2 from dns reaches neighbors-of-neighbors but not farther' do
        @root, _ = constellation
        g = described_class.scan(@root)
        set = g.cascade_set('platform-dns', max_depth: 2)
        # 1 hop: vpc, cache, builder-fleet. 2 hops: packer (via cache).
        # 3 hops would pick up iam (packer asks iam) — excluded at depth 2.
        expect(set).to include(
          'platform-dns', 'platform-vpc', 'platform-cache',
          'platform-builder-fleet', 'platform-packer'
        )
        expect(set).not_to include('platform-iam')
      end
    end
  end

  describe 'cascade.{pre,post}_actions in pangea.yml' do
    it 'loads declared pre_actions and post_actions' do
      Dir.mktmpdir do |dir|
        yml = {
          'workspace' => 'ws',
          'cascade' => { 'pre_actions' => %w[synth init], 'post_actions' => %w[output] },
        }
        File.write(File.join(dir, 'pangea.yml'), yml.to_yaml)
        ws = described_class::Workspace.load(dir)
        expect(ws.pre_actions).to eq(%w[synth init])
        expect(ws.post_actions).to eq(%w[output])
      end
    end

    it 'raises InvalidActionError when pre_action names a conflicting command' do
      Dir.mktmpdir do |dir|
        yml = {
          'workspace' => 'ws',
          'cascade' => { 'pre_actions' => %w[plan] },
        }
        File.write(File.join(dir, 'pangea.yml'), yml.to_yaml)
        expect { described_class::Workspace.load(dir) }.to raise_error(
          described_class::InvalidActionError, /conflicts with the primary command/
        )
      end
    end

    it 'raises InvalidActionError when action is not on the allowlist' do
      Dir.mktmpdir do |dir|
        yml = {
          'workspace' => 'ws',
          'cascade' => { 'post_actions' => %w[refresh] },
        }
        File.write(File.join(dir, 'pangea.yml'), yml.to_yaml)
        expect { described_class::Workspace.load(dir) }.to raise_error(
          described_class::InvalidActionError, /unknown cascade action/
        )
      end
    end
  end
end
