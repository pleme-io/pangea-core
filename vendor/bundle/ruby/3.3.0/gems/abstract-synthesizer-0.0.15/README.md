# Abstract Synthesizer 🏗️

[![Gem Version](https://badge.fury.io/rb/abstract-synthesizer.svg)](https://badge.fury.io/rb/abstract-synthesizer)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Ruby Version](https://img.shields.io/badge/ruby-%3E%3D3.3.0-red.svg)](https://ruby-lang.org)

**A powerful Ruby framework for creating declarative, verifiable configuration DSLs**

Abstract Synthesizer revolutionizes how Ruby applications handle configuration management by providing a robust foundation for building domain-specific languages (DSLs) that are both human-readable and machine-verifiable. Unlike traditional imperative configuration approaches, Abstract Synthesizer enables **declarative programming** patterns that result in more maintainable, predictable, and auditable systems.

## 📚 Table of Contents

- [🚀 Why Abstract Synthesizer?](#-why-abstract-synthesizer)
- [🌟 Key Features](#-key-features)
- [⚡ Installation](#-installation)
- [🏁 Quick Start](#-quick-start)
- [🎯 Real-World Applications](#-real-world-applications)
- [🔧 How It Works](#-how-it-works)
- [🌟 Why Declarative Programming Matters](#-why-declarative-programming-matters)
- [📖 Documentation](#-documentation)
- [🚀 Examples](#-examples)
- [🤝 Contributing](#-contributing)

## 🚀 Why Abstract Synthesizer?

### The Problem with Traditional Configuration Management

Most configuration systems suffer from:
- **Imperative complexity**: Step-by-step instructions that are hard to verify
- **State management issues**: Mutable configurations leading to drift
- **Lack of verifiability**: No way to validate end-state without execution
- **Poor composability**: Difficulty combining multiple configuration sources

### The Declarative Solution

Abstract Synthesizer addresses these challenges by providing:

- **🎯 Declarative Syntax**: Describe *what* you want, not *how* to achieve it
- **✅ Verifiable Manifests**: Generate immutable, inspectable configuration states
- **🔒 Type Safety**: Built-in validation prevents invalid configurations
- **🏗️ Composable Architecture**: Mix and match DSL components seamlessly
- **📊 Drift Detection**: Compare desired vs actual state for monitoring
- **🌊 Hierarchical Structure**: Natural nesting through Ruby metaprogramming

## 🌟 Key Features

### 🎨 Intuitive DSL Creation
Create custom configuration languages that feel natural:

```ruby
# Infrastructure DSL
infrastructure.synthesize do
  server :web, :production do
    image 'nginx:latest'
    replicas 3
    port 80
  end
  
  database :postgres, :primary do
    version '14'
    storage '100GB'
    backup_retention 30
  end
end
```

### 🔍 Built-in Validation
Prevent configuration errors at declaration time:

```ruby
# Only predefined resource types are allowed
synthesizer = SynthesizerFactory.create_synthesizer(
  name: :my_config,
  keys: %i[server database cache]  # Validation boundary
)

# This would raise InvalidSynthesizerKeyError
synthesizer.synthesize do
  invalid_resource do  # ❌ Not in allowed keys
    field 'value'
  end
end
```

### 📋 Verifiable Manifests
Generate immutable, inspectable configuration objects:

```ruby
manifest = synthesizer.synthesis
# => {
#   server: {
#     web: {
#       production: {
#         image: 'nginx:latest',
#         replicas: 3,
#         port: 80
#       }
#     }
#   }
# }

# Verify configuration completeness
errors = validate_manifest(manifest)
puts "✅ Configuration valid!" if errors.empty?
```

## ⚡ Installation

Add this line to your application's Gemfile:

```ruby
gem 'abstract-synthesizer'
```

And then execute:

```bash
bundle install
```

Or install it yourself as:

```bash
gem install abstract-synthesizer
```

## 🏁 Quick Start

```ruby
require 'abstract-synthesizer'

# Step 1: Define your domain vocabulary
resource_keys = %i[server database user]

# Step 2: Create a configured synthesizer
synthesizer = SynthesizerFactory.create_synthesizer(
  name: :my_config, 
  keys: resource_keys
)

# Step 3: Declare your desired state
synthesizer.synthesize do
  server :web_server, :production do
    host 'example.com'
    port 8080
    ssl true
  end

  database :main_db, :mysql do
    username 'admin'
    password 'secret'
    host 'db.example.com'
  end

  user :admin_user do
    name 'Administrator'
    email 'admin@example.com'
  end
end

# Step 4: Access the verifiable manifest
manifest = synthesizer.synthesis
puts manifest.inspect
# => Hierarchical hash representing your exact configuration
```

## 🎯 Real-World Applications

### 🏗️ Infrastructure as Code

Create Kubernetes deployment configurations with built-in validation:

```ruby
require_relative 'examples/infrastructure/kubernetes_deployment'

infrastructure = KubernetesInfrastructure.build do
  deployment :web_app, :production do
    image 'nginx:1.21'
    replicas 3
    container_port 80
    environment 'production'
  end
  
  service :web_app, :production do
    port 80
    target_port 80
    type 'LoadBalancer'
  end
  
  configmap :app_config, :production do
    database_url ENV['PROD_DB_URL']
    redis_url ENV['PROD_REDIS_URL']
    log_level 'info'
  end
end

# Verify before deployment
verification = infrastructure.verify_manifest
if verification[:valid]
  puts "✅ Deploying valid configuration..."
  kubernetes_yaml = infrastructure.to_kubernetes_yaml
  # Deploy to cluster...
else
  puts "❌ Configuration errors found:"
  verification[:errors].each { |error| puts "  - #{error}" }
  exit 1
end
```

### 🌐 API Configuration DSL

Define REST API routes and middleware declaratively:

```ruby
api_config = APIConfigSynthesizer.build do
  namespace :api, :v1 do
    middleware :authentication
    middleware :rate_limiting, requests: 1000, window: 3600
    
    resource :users do
      get :index, auth: true
      get :show, auth: true
      post :create, validation: UserSchema
      put :update, auth: true, validation: UserUpdateSchema
      delete :destroy, auth: true, admin_only: true
    end
    
    resource :posts do
      get :index, cache: 300
      get :show, cache: 600
      post :create, auth: true
    end
  end
end

# Generate OpenAPI specification
openapi_spec = api_config.to_openapi
# Generate route definitions
routes = api_config.to_rails_routes
```

### ⚙️ Build System Configuration

Create complex build pipelines with dependency management:

```ruby
build_config = BuildSystemSynthesizer.build do
  pipeline :web_app, :ci do
    stage :test do
      task :unit_tests, command: 'rspec'
      task :integration_tests, command: 'cucumber'
      task :lint, command: 'rubocop'
    end
    
    stage :build, depends_on: :test do
      task :compile_assets, command: 'rake assets:precompile'
      task :build_image, command: 'docker build -t app:${BUILD_ID} .'
    end
    
    stage :deploy, depends_on: :build do
      task :deploy_staging, 
           command: 'kubectl apply -f k8s/staging/',
           condition: 'branch == staging'
      task :deploy_production,
           command: 'kubectl apply -f k8s/production/',
           condition: 'branch == main'
    end
  end
end

# Generate CI/CD configurations
github_actions = build_config.to_github_actions
gitlab_ci = build_config.to_gitlab_ci
jenkins_file = build_config.to_jenkinsfile
```

## 🔧 How It Works

Abstract Synthesizer leverages Ruby's powerful metaprogramming capabilities to create a sophisticated two-phase DSL processing system:

### 🏗️ Architecture Overview

```
┌─────────────────┐    ┌──────────────────┐    ┌────────────────┐
│   DSL Source    │───▶│  Synthesizer     │───▶│   Verifiable   │
│   (Declarative) │    │  Engine          │    │   Manifest     │
└─────────────────┘    └──────────────────┘    └────────────────┘
         │                       │                       │
         ▼                       ▼                       ▼
   Ruby blocks with         Method missing +          Immutable hash
   domain vocabulary        Context switching         representing
                                                     desired state
```

### 🔄 Two-Phase Processing

#### Phase 1: Resource Declaration
When you declare a resource (e.g., `server :web, :production`):

1. **Validation**: Method name checked against allowed `keys`
2. **Context Setting**: `translation[:context]` = `:server`
3. **Path Building**: Arguments become nested keys `[:server, :web, :production]`
4. **Block Execution**: Enter field assignment mode

#### Phase 2: Field Assignment  
Inside resource blocks, field methods are processed:

1. **Context Awareness**: System knows we're in field assignment mode
2. **Path Extension**: Field name appended to current path
3. **Value Assignment**: Uses `bury` to create nested hash structure
4. **State Cleanup**: Context and path reset after block execution

### 🎯 Key Design Principles

#### **Declarative Over Imperative**
```ruby
# ❌ Imperative (HOW)
def setup_server
  server = create_server
  server.set_host('example.com')
  server.set_port(8080)
  server.enable_ssl
  return server
end

# ✅ Declarative (WHAT)
server :web, :production do
  host 'example.com'
  port 8080
  ssl true
end
```

#### **Validation-First Design**
- Resource types must be predefined (no typos, no unexpected resources)
- Field assignments validated for argument count
- Context switching prevents invalid nesting

#### **Immutable Manifests**
- Generated configurations are immutable hash structures
- Perfect for comparison, serialization, and verification
- Enable GitOps workflows and drift detection

### 🧠 Ruby Metaprogramming Magic

Abstract Synthesizer showcases advanced Ruby techniques:

#### **Dynamic Method Creation**
```ruby
# SynthesizerFactory creates methods at runtime
synthesizer.define_singleton_method(:method_missing) do |method_name, *args, &block|
  abstract_method_missing(method_name, keys, *args, &block)
end
```

#### **Context-Sensitive Processing**
```ruby
def valid_method?(method, keys)
  if translation[:context].nil?
    keys.include?(method)    # Resource space: strict validation
  else
    true                     # Field space: any method allowed
  end
end
```

#### **Hierarchical Path Management**
```ruby
translation[:ancestors].append(method.to_sym)     # Build path
translation[:ancestors].append(*args)             # Add arguments  
# Result: [:server, :web, :production, :host]
```

### 🔍 The Bury Pattern

The `bury` method enables deep hash assignment:

```ruby
# Instead of manual hash building:
hash[:server] ||= {}
hash[:server][:web] ||= {}  
hash[:server][:web][:production] ||= {}
hash[:server][:web][:production][:host] = 'example.com'

# Abstract Synthesizer does:
hash.bury(:server, :web, :production, :host, 'example.com')
```

This pattern ensures:
- **Automatic nesting**: No manual hash initialization
- **Path safety**: Won't overwrite existing intermediate values
- **Clean syntax**: Single operation for deep assignment

## Error Handling

Abstract Synthesizer provides specific error classes:

- `InvalidSynthesizerKeyError`: Raised when using undefined resource keys
- `TooManyFieldValuesError`: Raised when field assignments receive multiple arguments

```ruby
# This will raise InvalidSynthesizerKeyError
synthesizer.synthesize do
  invalid_resource do  # 'invalid_resource' not in keys
    field 'value'
  end
end

# This will raise TooManyFieldValuesError  
synthesizer.synthesize do
  server :web do
    port 8080, 3000  # Fields can only accept one value
  end
end
```

## 🌟 Why Declarative Programming Matters

### 📊 The Configuration Management Challenge

Modern software systems struggle with **configuration drift** - the gap between what configurations should be and what they actually are. Traditional imperative approaches make this problem worse:

- **Hard to verify**: You must execute scripts to understand end state
- **Difficult to audit**: Change history is buried in execution logs  
- **Prone to drift**: Manual changes bypass configuration management
- **Complex debugging**: Failures require understanding entire execution path

### ✅ Declarative Programming Benefits

Abstract Synthesizer's declarative approach solves these fundamental issues:

#### **🎯 Verifiable Manifests**
```ruby
# Generate immutable configuration state
manifest = synthesizer.synthesis
File.write('desired-state.json', manifest.to_json)

# Compare with actual state
actual_state = fetch_actual_infrastructure_state()
diff = compare_manifests(manifest, actual_state)

if diff.empty?
  puts "✅ No configuration drift detected"
else
  puts "⚠️  Drift detected: #{diff}"
  # Auto-remediate or alert
end
```

#### **🔒 Immutable Infrastructure**
- Configurations can't be accidentally modified after creation
- Every change requires going through the DSL (audit trail)
- Perfect for GitOps workflows

#### **🚀 Faster Development Cycles**
- Catch configuration errors at declaration time, not deployment time
- No need to execute scripts to understand what will happen
- Easy to test configurations with different parameters

#### **📈 Better Collaboration**
- Configurations are self-documenting
- Domain experts can review DSL code without understanding implementation
- Natural separation between "what" (DSL) and "how" (implementation)

### 🏗️ Standardizing Ruby Configuration

Abstract Synthesizer positions Ruby as a first-class language for **Infrastructure as Code** and **Configuration Management**, competing with:

| Tool | Language | Strength | Weakness |
|------|----------|----------|----------|
| **Terraform** | HCL (DSL) | Infrastructure focus | Limited programming features |
| **Puppet** | Puppet DSL | System config focus | Learning curve |
| **Chef** | Ruby DSL | Full Ruby power | Complex for simple tasks |
| **Abstract Synthesizer** | **Ruby DSL** | **Best of both worlds** | **New ecosystem** |

#### **Advantages Over Existing Tools:**

1. **Native Ruby Integration**: Works seamlessly with existing Ruby applications
2. **Lightweight**: No complex agents or infrastructure required  
3. **Flexible**: Create DSLs for any domain, not just infrastructure
4. **Type Safe**: Built-in validation prevents entire classes of errors
5. **Composable**: Mix multiple synthesizers in the same application

### 🔄 GitOps and DevOps Integration

Abstract Synthesizer enables modern DevOps practices:

#### **GitOps Workflow**
```ruby
# 1. Define infrastructure declaratively
infrastructure = ProductionInfrastructure.build do
  cluster :main, :us_west_2 do
    node_count 5
    instance_type 'm5.large'
  end
end

# 2. Verify before applying
verification = infrastructure.verify()
raise "Invalid config: #{verification[:errors]}" unless verification[:valid]

# 3. Generate deployment artifacts
kubernetes_manifests = infrastructure.to_kubernetes
terraform_config = infrastructure.to_terraform

# 4. Apply through GitOps
commit_to_git(kubernetes_manifests)
# ArgoCD/Flux will detect changes and apply automatically
```

#### **Configuration Drift Detection**
```ruby
class DriftDetector
  def self.check_infrastructure(synthesizer_instance)
    desired = synthesizer_instance.synthesis
    actual = fetch_actual_state_from_cluster()
    
    drift = compare_states(desired, actual)
    
    if drift.any?
      alert_team("Configuration drift detected: #{drift}")
      auto_remediate(drift) if auto_remediation_enabled?
    end
  end
end
```

### 🔬 Advanced Use Cases

#### **Multi-Environment Configuration**
```ruby
%w[development staging production].each do |env|
  config = AppConfiguration.build do
    database :primary, env.to_sym do
      host ENV["#{env.upcase}_DB_HOST"]
      replicas env == 'production' ? 3 : 1
      backup_retention env == 'production' ? 30 : 7
    end
    
    cache :redis, env.to_sym do
      memory env == 'production' ? '2GB' : '512MB'
      persistence env == 'production' ? true : false
    end
  end
  
  File.write("config/#{env}.json", config.synthesis.to_json)
end
```

#### **Configuration Validation Pipeline**
```ruby
class ConfigurationPipeline
  def self.validate_and_deploy(config_synthesizer)
    # Stage 1: Syntax validation (automatic)
    # Stage 2: Business rules validation  
    validate_business_rules(config_synthesizer)
    
    # Stage 3: Security validation
    validate_security_policies(config_synthesizer)
    
    # Stage 4: Cost estimation
    estimated_cost = estimate_infrastructure_cost(config_synthesizer)
    raise "Budget exceeded: $#{estimated_cost}" if estimated_cost > MAX_BUDGET
    
    # Stage 5: Deploy
    deploy_configuration(config_synthesizer)
  end
end
```

## 📖 Documentation

- **[Overview](docs/overview.md)** - Architecture and core concepts
- **[Usage Guide](docs/usage.md)** - Detailed usage instructions and patterns
- **[Examples](examples/)** - Real-world examples across different domains
- **[API Reference](lib/)** - Source code and implementation details

## 🚀 Examples

Explore comprehensive examples showing Abstract Synthesizer in action:

- **[🏗️ Infrastructure as Code](examples/infrastructure/)** - Kubernetes deployments and container orchestration
- **[🌐 API Configuration](examples/api/)** - REST API route generation and OpenAPI specs  
- **[⚙️ Build Systems](examples/build_system/)** - CI/CD pipelines for multiple platforms
- **[📊 Configuration Management](examples/configuration_management/)** - Application config with drift detection

Each example is a complete, runnable demonstration with validation, error handling, and multi-format output generation.

## 🛠️ Development

After checking out the repo, run:

```bash
bundle install
```

To run tests:

```bash
bundle exec rspec
```

To run linting:

```bash
bundle exec rubocop
```

## 🤝 Contributing

We welcome contributions! Please see [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines on:

- Reporting issues
- Submitting changes
- Development setup
- Code standards
- Testing requirements

## 📄 License

The gem is available as open source under the terms of the [MIT License](LICENSE).
