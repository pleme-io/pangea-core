# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Pangea::Entities::Project do
  let(:basic_project) do
    described_class.new(name: 'web-app', namespace: 'production')
  end

  let(:full_project) do
    described_class.new(
      name: 'api-server',
      namespace: 'staging',
      site: 'us-east',
      description: 'API server project',
      modules: ['vpc-module', 'iam-module'],
      variables: { region: 'us-east-1' },
      outputs: ['vpc_id'],
      depends_on: ['base-infra'],
      terraform_version: '1.5.0',
      tags: { team: 'platform' }
    )
  end

  describe 'initialization' do
    it 'creates with minimal attributes' do
      expect(basic_project.name).to eq('web-app')
      expect(basic_project.namespace).to eq('production')
    end

    it 'defaults site to nil' do
      expect(basic_project.site).to be_nil
    end

    it 'defaults modules to empty array' do
      expect(basic_project.modules).to eq([])
    end

    it 'defaults depends_on to empty array' do
      expect(basic_project.depends_on).to eq([])
    end

    it 'defaults tags to empty hash' do
      expect(basic_project.tags).to eq({})
    end
  end

  describe '#full_name' do
    it 'joins namespace and name' do
      expect(basic_project.full_name).to eq('production.web-app')
    end

    it 'includes site when present' do
      expect(full_project.full_name).to eq('staging.us-east.api-server')
    end
  end

  describe '#state_key' do
    it 'joins namespace and name with /' do
      expect(basic_project.state_key).to eq('production/web-app')
    end

    it 'includes site when present' do
      expect(full_project.state_key).to eq('staging/us-east/api-server')
    end
  end

  describe '#has_modules?' do
    it 'returns false when no modules' do
      expect(basic_project.has_modules?).to be false
    end

    it 'returns true when modules exist' do
      expect(full_project.has_modules?).to be true
    end
  end

  describe '#has_dependencies?' do
    it 'returns false when no dependencies' do
      expect(basic_project.has_dependencies?).to be false
    end

    it 'returns true when dependencies exist' do
      expect(full_project.has_dependencies?).to be true
    end
  end

  describe '#module_config' do
    it 'finds a module by name' do
      expect(full_project.module_config('vpc-module')).to eq('vpc-module')
    end

    it 'returns nil for unknown module' do
      expect(full_project.module_config('unknown')).to be_nil
    end
  end

  describe '#to_backend_config' do
    it 'generates backend config with state key' do
      config = basic_project.to_backend_config
      expect(config[:key]).to eq('production/web-app')
      expect(config[:workspace_key_prefix]).to eq('workspaces')
    end

    it 'prepends prefix when provided' do
      config = basic_project.to_backend_config(prefix: 'terraform')
      expect(config[:key]).to eq('terraform/production/web-app')
    end
  end

  describe '#validate!' do
    it 'passes for valid project' do
      expect(basic_project.validate!).to be true
    end

    it 'raises when project depends on itself' do
      proj = described_class.new(
        name: 'circular',
        namespace: 'test',
        depends_on: ['circular']
      )
      expect { proj.validate! }.to raise_error(
        Pangea::Entities::ValidationError, /cannot depend on itself/
      )
    end

    it 'rejects invalid module names at construction time via type constraint' do
      expect {
        described_class.new(
          name: 'test',
          namespace: 'test',
          modules: ['valid-mod', 'INVALID']
        )
      }.to raise_error(Dry::Struct::Error)
    end
  end
end
