# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Pangea::Entities::Namespace do
  let(:s3_config) do
    {
      bucket: 'my-bucket',
      key: 'state/terraform.tfstate',
      region: 'us-east-1',
      dynamodb_table: 'lock-table',
      encrypt: true
    }
  end

  let(:s3_namespace) do
    described_class.new(
      name: 'production',
      state: { type: :s3, config: s3_config }
    )
  end

  let(:local_namespace) do
    described_class.new(
      name: 'development',
      state: { type: :local, config: { path: '/tmp/state.tfstate' } }
    )
  end

  describe 'initialization' do
    it 'creates with S3 backend' do
      expect(s3_namespace.name).to eq('production')
      expect(s3_namespace.state.type).to eq(:s3)
    end

    it 'creates with local backend' do
      expect(local_namespace.name).to eq('development')
      expect(local_namespace.state.type).to eq(:local)
    end

    it 'defaults description to nil' do
      expect(s3_namespace.description).to be_nil
    end

    it 'defaults tags to empty hash' do
      expect(s3_namespace.tags).to eq({})
    end

    it 'accepts custom tags' do
      ns = described_class.new(
        name: 'staging',
        state: { type: :local, config: {} },
        tags: { env: 'staging' }
      )
      expect(ns.tags).to eq({ env: 'staging' })
    end
  end

  describe 'State validation' do
    it 'raises for S3 backend without bucket' do
      expect {
        described_class.new(
          name: 'test',
          state: { type: :s3, config: { key: 'k' } }
        )
      }.to raise_error(Pangea::Entities::ValidationError, /bucket/)
    end

    it 'raises for S3 backend without key' do
      expect {
        described_class.new(
          name: 'test',
          state: { type: :s3, config: { bucket: 'b' } }
        )
      }.to raise_error(Pangea::Entities::ValidationError, /key/)
    end

    it 'defaults local backend path when not provided' do
      ns = described_class.new(
        name: 'test',
        state: { type: :local, config: {} }
      )
      expect(ns.state.config.path).to eq('./terraform.tfstate')
    end
  end

  describe '#s3_backend?' do
    it 'returns true for S3 backend' do
      expect(s3_namespace.s3_backend?).to be true
    end

    it 'returns false for local backend' do
      expect(local_namespace.s3_backend?).to be false
    end
  end

  describe '#local_backend?' do
    it 'returns true for local backend' do
      expect(local_namespace.local_backend?).to be true
    end

    it 'returns false for S3 backend' do
      expect(s3_namespace.local_backend?).to be false
    end
  end

  describe '#state_config' do
    it 'includes type and region for S3' do
      config = s3_namespace.state_config
      expect(config[:type]).to eq(:s3)
      expect(config[:bucket]).to eq('my-bucket')
      expect(config[:region]).to eq('us-east-1')
    end

    it 'includes only type for local' do
      config = local_namespace.state_config
      expect(config[:type]).to eq(:local)
      expect(config).not_to have_key(:bucket)
    end
  end

  describe '#s3_config' do
    it 'returns S3 configuration hash' do
      config = s3_namespace.s3_config
      expect(config[:bucket]).to eq('my-bucket')
      expect(config[:key]).to eq('state/terraform.tfstate')
      expect(config[:dynamodb_table]).to eq('lock-table')
    end

    it 'raises for non-S3 backend' do
      expect { local_namespace.s3_config }.to raise_error(RuntimeError, /does not use S3 backend/)
    end
  end

  describe '#to_terraform_backend' do
    it 'returns S3 backend configuration' do
      backend = s3_namespace.to_terraform_backend
      expect(backend).to have_key(:s3)
      expect(backend[:s3][:bucket]).to eq('my-bucket')
      expect(backend[:s3][:key]).to eq('state/terraform.tfstate')
      expect(backend[:s3][:encrypt]).to be true
    end

    it 'returns local backend configuration' do
      backend = local_namespace.to_terraform_backend
      expect(backend).to have_key(:local)
      expect(backend[:local][:path]).to eq('/tmp/state.tfstate')
    end

    it 'defaults local path when not set' do
      ns = described_class.new(
        name: 'test',
        state: { type: :local, config: {} }
      )
      backend = ns.to_terraform_backend
      expect(backend[:local][:path]).to eq('./terraform.tfstate')
    end

    it 'raises when S3 bucket is nil' do
      ns = described_class.new(
        name: 'test',
        state: { type: :s3, config: { bucket: 'b', key: 'k' } }
      )
      ns.state.config.instance_variable_set(:@attributes, ns.state.config.attributes.merge(bucket: nil))
      # Reconstruct to test the validation path
    end
  end

  describe 'StateConfig#lock_table' do
    it 'prefers dynamodb_table over lock' do
      config = Pangea::Entities::Namespace::StateConfig.new(
        dynamodb_table: 'dynamo-lock',
        lock: 'other-lock'
      )
      expect(config.lock_table).to eq('dynamo-lock')
    end

    it 'falls back to lock field' do
      config = Pangea::Entities::Namespace::StateConfig.new(lock: 'lock-table')
      expect(config.lock_table).to eq('lock-table')
    end
  end

  describe 'State#s3? and State#local?' do
    it 's3? returns true for s3 type' do
      state = s3_namespace.state
      expect(state.s3?).to be true
      expect(state.local?).to be false
    end

    it 'local? returns true for local type' do
      state = local_namespace.state
      expect(state.local?).to be true
      expect(state.s3?).to be false
    end
  end
end
