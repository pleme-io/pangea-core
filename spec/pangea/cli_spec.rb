# frozen_string_literal: true

require 'spec_helper'
require 'pangea/cli'

RSpec.describe Pangea::CLI do
  describe '.parse (via .send for private method)' do
    it 'extracts --depth integer into options[:depth]' do
      argv = ['plan', 'foo.rb', '--depth', '2']
      allow(File).to receive(:exist?).with('foo.rb').and_return(true)
      op, tmpl, ns, bulk, opts = described_class.send(:parse, argv)
      expect(op).to eq('plan')
      expect(tmpl).to eq('foo.rb')
      expect(opts[:depth]).to eq(2)
      expect(opts[:no_cascade]).to be(false)
    end

    it 'supports the short -D flag' do
      argv = ['plan', 'foo.rb', '-D', '0']
      allow(File).to receive(:exist?).with('foo.rb').and_return(true)
      _, _, _, _, opts = described_class.send(:parse, argv)
      expect(opts[:depth]).to eq(0)
    end

    it 'extracts --no-cascade as a boolean switch' do
      argv = ['plan', 'foo.rb', '--no-cascade']
      allow(File).to receive(:exist?).with('foo.rb').and_return(true)
      _, _, _, _, opts = described_class.send(:parse, argv)
      expect(opts[:no_cascade]).to be(true)
      expect(opts[:depth]).to be_nil
    end

    it 'leaves options[:depth] nil when --depth omitted' do
      argv = ['plan', 'foo.rb']
      allow(File).to receive(:exist?).with('foo.rb').and_return(true)
      _, _, _, _, opts = described_class.send(:parse, argv)
      expect(opts[:depth]).to be_nil
    end

    it 'exits with error for non-integer --depth value' do
      argv = ['plan', 'foo.rb', '--depth', 'nope']
      allow(File).to receive(:exist?).with('foo.rb').and_return(true)
      allow($stderr).to receive(:puts)
      expect { described_class.send(:parse, argv) }.to raise_error(SystemExit)
    end

    it 'exits with error for negative --depth value' do
      argv = ['plan', 'foo.rb', '--depth', '-1']
      allow(File).to receive(:exist?).with('foo.rb').and_return(true)
      allow($stderr).to receive(:puts)
      expect { described_class.send(:parse, argv) }.to raise_error(SystemExit)
    end
  end
end
