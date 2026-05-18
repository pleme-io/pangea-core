# frozen_string_literal: true

require 'pangea/magma/stack'
require 'pangea/magma/workspace'
require 'pangea/magma/optimization'

# Pangea::Magma::Stack.build — high-level orchestrator helper that
# auto-derives cross-tier typed edges by name-matching upstream
# outputs to downstream inputs. These specs lock in the invariants
# the helper guarantees.
RSpec.describe Pangea::Magma::Stack do
  def ws(name, **slots)
    Pangea::Magma::Workspace.declare(
      name: name, template: 'noop.rb', workspace_dir: "/tmp/#{name}",
      **slots,
    )
  end

  describe '.build' do
    it 'auto-derives a typed edge when upstream output name matches downstream input name' do
      upstream   = ws(:up,  outputs: { x: { type: String } })
      downstream = ws(:dn,  inputs:  { x: { type: String } })

      stack = described_class.build(
        name: :t1,
        tiers: { a: [upstream], b: [downstream] },
      )

      expect(stack.chain.edges.size).to eq(1)
      e = stack.chain.edges.first
      expect(e.from).to eq(:up)
      expect(e.to).to eq(:dn)
      expect(e.from_output).to eq(:x)
      expect(e.to_input).to eq(:x)
    end

    it 'does NOT derive edges when names do not match' do
      u = ws(:u, outputs: { vpc_id: { type: String } })
      d = ws(:d, inputs:  { subnet_id: { type: String } })

      stack = described_class.build(name: :t, tiers: { a: [u], b: [d] })
      expect(stack.chain.edges).to be_empty
    end

    it 'honors explicitly-passed edges over auto-derivation' do
      u = ws(:u, outputs: { foo: { type: String }, bar: { type: String } })
      d = ws(:d, inputs:  { foo: { type: String }, bar: { type: String } })

      stack = described_class.build(
        name:  :t,
        tiers: { a: [u], b: [d] },
        edges: [{ from: :u, output: :foo, to: :d, input: :foo }],
      )

      expect(stack.chain.edges.size).to eq(1)
      expect(stack.chain.edges.first.from_output).to eq(:foo)
    end

    it 'rejects explicit edges that reference unknown workspaces' do
      u = ws(:u, outputs: { x: { type: String } })

      expect {
        described_class.build(
          name: :t, tiers: { a: [u] },
          edges: [{ from: :u, output: :x, to: :ghost, input: :x }],
        )
      }.to raise_error(ArgumentError, /unknown workspace: ghost/)
    end

    it 'accepts Optimization as a Hash' do
      u = ws(:u, outputs: { x: { type: String } })
      d = ws(:d, inputs:  { x: { type: String } })

      stack = described_class.build(
        name:  :t,
        tiers: { a: [u], b: [d] },
        optimization: { strategy: :parallel_by_tier, max_concurrency: 8 },
      )

      expect(stack.optimization).to be_a(Pangea::Magma::Optimization)
      expect(stack.optimization.max_concurrency).to eq(8)
      expect(stack.chain.optimization).to be(stack.optimization)
    end

    it 'accepts Optimization as an instance' do
      u = ws(:u); d = ws(:d)
      opt = Pangea::Magma::Optimization.parallel_by_tier(max_concurrency: 16)
      stack = described_class.build(name: :t, tiers: { a: [u], b: [d] }, optimization: opt)
      expect(stack.optimization.max_concurrency).to eq(16)
    end

    it 'composes a three-tier stack with both transitions auto-derived' do
      a = ws(:a, outputs: { token: { type: String } })
      b = ws(:b, inputs:  { token: { type: String } },
                 outputs: { kubeconfig: { type: String } })
      c = ws(:c, inputs:  { kubeconfig: { type: String } })

      stack = described_class.build(
        name:  :three,
        tiers: { auth: [a], cluster: [b], workload: [c] },
      )

      expect(stack.chain.edges.size).to eq(2)
      transitions = stack.chain.edges.map { |e| [e.from, e.to, e.from_output] }
      expect(transitions).to contain_exactly([:a, :b, :token], [:b, :c, :kubeconfig])
    end

    it 'exposes the underlying Distribution + Orchestrator + Chain' do
      u = ws(:u); d = ws(:d)
      stack = described_class.build(name: :t, tiers: { a: [u], b: [d] })
      expect(stack.distribution).to be_a(Pangea::Magma::Distribution)
      expect(stack.orchestrator).to be_a(Pangea::Magma::Orchestrator)
      expect(stack.chain).to be_a(Pangea::Magma::Chain)
    end
  end
end
