# frozen_string_literal: true

require 'pangea/outputs'

RSpec.describe Pangea::Outputs do
  # Create a minimal synthesizer-like context for testing
  let(:context) do
    obj = Object.new
    obj.extend(described_class)

    # Track output calls
    outputs = {}
    obj.define_singleton_method(:output) do |name, &block|
      outputs[name] = block
    end
    obj.define_singleton_method(:emitted_outputs) { outputs }

    obj
  end

  describe '#pangea_output_config' do
    it 'defaults to all outputs enabled' do
      expect(context.pangea_output_config).to eq({ display: true, data: true })
    end

    it 'can be overridden' do
      context.pangea_output_config = { display: false }
      expect(context.pangea_output_config[:display]).to be false
      expect(context.pangea_output_config[:data]).to be true
    end
  end

  describe '#pangea_output' do
    it 'emits output when category is enabled' do
      context.pangea_output(:vpc_id, category: :data) { 'value' }
      expect(context.emitted_outputs).to have_key(:vpc_id)
    end

    it 'suppresses output when category is disabled' do
      context.pangea_output_config = { data: false }
      context.pangea_output(:vpc_id, category: :data) { 'value' }
      expect(context.emitted_outputs).not_to have_key(:vpc_id)
    end

    it 'defaults category to :data' do
      context.pangea_output(:vpc_id) { 'value' }
      expect(context.emitted_outputs).to have_key(:vpc_id)
    end

    it 'respects display category independently' do
      context.pangea_output_config = { display: false, data: true }
      context.pangea_output(:cluster_name, category: :display) { 'name' }
      context.pangea_output(:vpc_id, category: :data) { 'vpc-123' }
      expect(context.emitted_outputs).not_to have_key(:cluster_name)
      expect(context.emitted_outputs).to have_key(:vpc_id)
    end

    it 'suppresses all when both categories disabled' do
      context.pangea_output_config = { display: false, data: false }
      context.pangea_output(:cluster_name, category: :display) { 'name' }
      context.pangea_output(:vpc_id, category: :data) { 'vpc-123' }
      expect(context.emitted_outputs).to be_empty
    end
  end

  describe '#display_output' do
    it 'creates a display-category output' do
      context.display_output(:cluster_name) { 'name' }
      expect(context.emitted_outputs).to have_key(:cluster_name)
    end

    it 'is suppressed when display is off' do
      context.pangea_output_config = { display: false }
      context.display_output(:cluster_name) { 'name' }
      expect(context.emitted_outputs).not_to have_key(:cluster_name)
    end
  end

  describe '#data_output' do
    it 'creates a data-category output' do
      context.data_output(:vpc_id) { 'vpc-123' }
      expect(context.emitted_outputs).to have_key(:vpc_id)
    end

    it 'is suppressed when data is off' do
      context.pangea_output_config = { data: false }
      context.data_output(:vpc_id) { 'vpc-123' }
      expect(context.emitted_outputs).not_to have_key(:vpc_id)
    end
  end

  describe '#suppress_all_outputs!' do
    it 'disables all output categories' do
      context.suppress_all_outputs!
      context.display_output(:name) { 'x' }
      context.data_output(:id) { 'y' }
      expect(context.emitted_outputs).to be_empty
    end
  end

  describe '#suppress_display_outputs!' do
    it 'disables display but keeps data' do
      context.suppress_display_outputs!
      context.display_output(:name) { 'x' }
      context.data_output(:id) { 'y' }
      expect(context.emitted_outputs).not_to have_key(:name)
      expect(context.emitted_outputs).to have_key(:id)
    end
  end

  describe '#enable_all_outputs!' do
    it 'enables all categories' do
      context.suppress_all_outputs!
      context.enable_all_outputs!
      context.display_output(:name) { 'x' }
      context.data_output(:id) { 'y' }
      expect(context.emitted_outputs).to have_key(:name)
      expect(context.emitted_outputs).to have_key(:id)
    end
  end

  describe 'unknown categories' do
    it 'emits output for unknown categories (defaults to enabled)' do
      context.pangea_output(:custom, category: :custom) { 'val' }
      expect(context.emitted_outputs).to have_key(:custom)
    end

    it 'still respects master kill switch for unknown categories' do
      context.pangea_output_config = { display: false, data: false }
      context.pangea_output(:custom, category: :custom) { 'val' }
      expect(context.emitted_outputs).not_to have_key(:custom)
    end
  end
end
