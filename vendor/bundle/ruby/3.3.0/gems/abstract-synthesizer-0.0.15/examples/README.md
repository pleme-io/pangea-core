# Abstract Synthesizer Examples

> **📋 Navigation**: [Main README](../README.md) | [Overview](../docs/overview.md) | [Usage Guide](../docs/usage.md) | **Examples**

This directory contains comprehensive examples demonstrating the power and flexibility of Abstract Synthesizer across different domains. Each example is a complete, runnable demonstration showcasing real-world applications.

## 📚 Quick Navigation

- [🏗️ Infrastructure as Code](#️-infrastructure-as-code) - Kubernetes deployments
- [🌐 API Configuration](#-api-configuration) - REST API route generation  
- [⚙️ Build Systems](#️-build-systems) - CI/CD pipeline configuration
- [📊 Configuration Management](#-configuration-management) - Application configuration with validation

## 🏗️ Infrastructure as Code

### [Kubernetes Deployment DSL](infrastructure/kubernetes_deployment.rb)

Create declarative Kubernetes configurations with built-in validation:

```ruby
infrastructure = KubernetesInfrastructure.build do
  deployment :web_app, :production do
    image 'nginx:1.21'
    replicas 3
    container_port 80
  end
  
  service :web_app, :production do
    port 80
    target_port 80
    type 'LoadBalancer'
  end
end

# Verify and generate YAML
if infrastructure.verify_manifest[:valid]
  puts infrastructure.to_kubernetes_yaml
end
```

**Features demonstrated:**
- Resource validation
- Multi-environment support  
- YAML generation
- Manifest verification

## 🌐 API Configuration

### [REST API DSL](api/rest_api_dsl.rb)

Define REST APIs declaratively with automatic route generation:

```ruby
api_config = RestAPIConfiguration.build do
  namespace :api, :v1 do
    middleware :authentication
    middleware :rate_limiting, requests: 1000
    
    resource :users do
      get :index, auth: true, cache: 300
      post :create, validation: :UserSchema
    end
  end
end

# Generate Rails routes and OpenAPI spec
puts api_config.to_rails_routes
puts api_config.to_openapi.to_json
```

**Features demonstrated:**
- Nested namespaces
- Middleware configuration
- Route generation for multiple frameworks
- OpenAPI specification generation
- Built-in validation

## ⚙️ Build Systems

### [CI/CD Pipeline DSL](build_system/ci_cd_pipeline.rb)

Create complex build pipelines with dependency management:

```ruby
pipeline = CICDPipelineConfiguration.build do
  pipeline :web_app, :ci do
    stage :test do
      task :unit_tests, command: 'rspec'
      task :lint, command: 'rubocop'
    end
    
    stage :deploy, depends_on: :test do
      task :deploy_production,
           command: 'kubectl apply -f k8s/',
           condition: 'branch == main'
    end
  end
end

# Generate CI/CD configs for different platforms
puts pipeline.to_github_actions.to_yaml
puts pipeline.to_gitlab_ci.to_yaml
puts pipeline.to_jenkinsfile
```

**Features demonstrated:**
- Stage dependencies
- Conditional execution
- Multi-platform generation (GitHub Actions, GitLab CI, Jenkins)
- Notification configuration
- Artifact management

## 📊 Configuration Management

### [Application Configuration DSL](configuration_management/app_config_dsl.rb)

Manage complex application configurations with validation and drift detection:

```ruby
config = ApplicationConfigurationManager.build(environment: :production) do
  database :primary, :postgresql do
    host ENV['PROD_DB_HOST']
    ssl true
    connection_pool 20
  end
  
  security :authentication, :jwt do
    secret ENV['JWT_SECRET']
    expiry 3600
  end
  
  feature :new_ui, :beta do
    enabled true
    rollout_percentage 25
  end
end

# Comprehensive validation
verification = config.verify_manifest
puts "Valid: #{verification[:valid]}"
puts "Errors: #{verification[:errors]}"
puts "Warnings: #{verification[:warnings]}"

# Generate deployment artifacts
puts config.to_env_file        # Environment variables
puts config.to_yaml           # YAML configuration
puts config.generate_deployment_checklist  # Deployment checklist
```

**Features demonstrated:**
- Environment-specific configurations
- Multi-format output (ENV, YAML, JSON)
- Comprehensive validation with warnings
- Configuration drift detection
- Deployment checklists
- Security best practices validation

## 🎯 Key Benefits Demonstrated

### 1. **Declarative Over Imperative**
All examples show how to declare *what* you want rather than *how* to achieve it.

### 2. **Built-in Validation**
Every DSL includes comprehensive validation that catches errors early.

### 3. **Multi-Format Generation**
Generate configuration files for different tools and platforms from a single source.

### 4. **Verifiable Manifests**
All configurations produce inspectable, immutable manifests for auditing.

### 5. **Environment Awareness**
Support for multiple environments with environment-specific validation.

### 6. **Drift Detection**
Compare desired state with actual state to detect configuration drift.

## 🚀 Running the Examples

Each example is a standalone Ruby script that can be executed directly:

```bash
# Run infrastructure example
ruby examples/infrastructure/kubernetes_deployment.rb

# Run API configuration example  
ruby examples/api/rest_api_dsl.rb

# Run build pipeline example
ruby examples/build_system/ci_cd_pipeline.rb

# Run configuration management example
ruby examples/configuration_management/app_config_dsl.rb
```

## 🧩 Creating Your Own DSLs

These examples serve as templates for creating your own domain-specific languages:

1. **Define your domain vocabulary** (the `keys` array)
2. **Create a wrapper class** with build methods
3. **Add validation logic** specific to your domain
4. **Implement output formats** for your target systems
5. **Add verification methods** for configuration validation

## 💡 Best Practices Demonstrated

- **Single Responsibility**: Each DSL focuses on one domain
- **Validation First**: Validate configurations before processing
- **Immutable Outputs**: Generate immutable configuration artifacts
- **Error Handling**: Provide clear, actionable error messages
- **Documentation**: Self-documenting configuration through clear DSL syntax
- **Testing**: Easy to test configurations without side effects

These examples showcase how Abstract Synthesizer can standardize declarative programming patterns across Ruby applications while maintaining type safety, verifiability, and ease of use.

---

## 🔗 Related Documentation

- **[Main README](../README.md)** - Project overview and getting started
- **[Architecture Overview](../docs/overview.md)** - Technical implementation details
- **[Usage Guide](../docs/usage.md)** - Comprehensive patterns and best practices

## 💡 Next Steps

1. **Run the examples** - Each file is executable: `ruby examples/infrastructure/kubernetes_deployment.rb`
2. **Study the patterns** - Each example demonstrates different DSL design approaches
3. **Build your own** - Use these as templates for your domain-specific DSLs
4. **Contribute** - Share your own examples via pull requests!