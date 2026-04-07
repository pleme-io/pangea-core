# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Pangea::Entities::Template do
  let(:inline_template) do
    described_class.new(
      name: 'test-template',
      content: 'template :test do; end'
    )
  end

  let(:file_template) do
    described_class.new(
      name: 'file-template',
      content: "# @author: Test\n# @version: 1.0\ntemplate :file do; end",
      file_path: '/path/to/template.rb',
      namespace: 'production',
      project: 'web-app'
    )
  end

  describe 'initialization' do
    it 'creates with minimal attributes' do
      expect(inline_template.name).to eq('test-template')
      expect(inline_template.content).to eq('template :test do; end')
    end

    it 'defaults file_path to nil' do
      expect(inline_template.file_path).to be_nil
    end

    it 'defaults strict_mode to false' do
      expect(inline_template.strict_mode).to be false
    end

    it 'defaults variables to empty hash' do
      expect(inline_template.variables).to eq({})
    end
  end

  describe '#source' do
    it 'returns file_path when available' do
      expect(file_template.source).to eq('/path/to/template.rb')
    end

    it 'returns inline placeholder when no file_path' do
      expect(inline_template.source).to eq('<inline:test-template>')
    end
  end

  describe '#from_file?' do
    it 'returns true when file_path is set' do
      expect(file_template.from_file?).to be true
    end

    it 'returns false when file_path is nil' do
      expect(inline_template.from_file?).to be false
    end
  end

  describe '#cache_key' do
    it 'returns just the name for inline templates' do
      expect(inline_template.cache_key).to eq('test-template')
    end

    it 'joins namespace, project, and name' do
      expect(file_template.cache_key).to eq('production/web-app/file-template')
    end
  end

  describe '#validate!' do
    it 'passes for valid template' do
      expect(inline_template.validate!).to be true
    end

    it 'raises for empty content' do
      tmpl = described_class.new(name: 'empty', content: '   ')
      expect { tmpl.validate! }.to raise_error(
        Pangea::Entities::ValidationError, /content cannot be empty/
      )
    end

    it 'raises for ERB syntax' do
      tmpl = described_class.new(name: 'erb', content: '<%= foo %>')
      expect { tmpl.validate! }.to raise_error(
        Pangea::Entities::ValidationError, /ERB or Mustache/
      )
    end

    it 'raises for Mustache syntax' do
      tmpl = described_class.new(name: 'mustache', content: '{{ var }}')
      expect { tmpl.validate! }.to raise_error(
        Pangea::Entities::ValidationError, /ERB or Mustache/
      )
    end
  end

  describe '#metadata' do
    it 'extracts metadata annotations from content' do
      meta = file_template.metadata
      expect(meta[:author]).to eq('Test')
      expect(meta[:version]).to eq('1.0')
    end

    it 'returns empty hash for content without annotations' do
      expect(inline_template.metadata).to eq({})
    end
  end

  describe '#content_without_metadata' do
    it 'strips metadata lines' do
      expect(file_template.content_without_metadata).to eq("template :file do; end")
    end

    it 'returns full content when no metadata' do
      expect(inline_template.content_without_metadata).to eq('template :test do; end')
    end
  end
end

RSpec.describe Pangea::Entities::CompilationResult do
  describe '#success?' do
    it 'returns true when success is true and no errors' do
      result = described_class.new(success: true)
      expect(result.success?).to be true
    end

    it 'returns false when success is false' do
      result = described_class.new(success: false)
      expect(result.success?).to be false
    end

    it 'returns false when errors are present even if success is true' do
      result = described_class.new(success: true, errors: ['something failed'])
      expect(result.success?).to be false
    end
  end

  describe '#failure?' do
    it 'returns true when not successful' do
      result = described_class.new(success: false)
      expect(result.failure?).to be true
    end

    it 'returns false when successful' do
      result = described_class.new(success: true)
      expect(result.failure?).to be false
    end
  end

  describe 'defaults' do
    it 'defaults errors to empty array' do
      result = described_class.new(success: true)
      expect(result.errors).to eq([])
    end

    it 'defaults warnings to empty array' do
      result = described_class.new(success: true)
      expect(result.warnings).to eq([])
    end
  end
end
