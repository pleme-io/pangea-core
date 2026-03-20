# Abstract Synthesizer - Usage Guide

> **📋 Navigation**: [Main README](../README.md) | [Overview](overview.md) | **Usage Guide** | [Examples](../examples/)

This comprehensive guide shows you how to use Abstract Synthesizer to create powerful, declarative configuration DSLs for your Ruby applications.

## 📚 Table of Contents

- [⚡ Quick Start](#-quick-start)
- [🔧 Core Concepts](#-core-concepts)
- [🎨 Creating DSLs](#-creating-dsls)
- [✅ Validation Patterns](#-validation-patterns)
- [🔍 Error Handling](#-error-handling)
- [🚀 Advanced Patterns](#-advanced-patterns)
- [💡 Best Practices](#-best-practices)

## ⚡ Quick Start

```ruby
require 'abstract-synthesizer'

# Step 1: Define your domain vocabulary
resource_keys = %i[server database cache]

# Step 2: Create a synthesizer
synthesizer = SynthesizerFactory.create_synthesizer(
  name: :my_config,
  keys: resource_keys
)

# Step 3: Declare your configuration
synthesizer.synthesize do
  server :web, :production do
    host 'api.example.com'
    port 443
    ssl true
  end

  database :primary, :postgresql do
    host 'db.example.com'
    port 5432
    ssl_mode 'require'
  end
end

# Step 4: Access the manifest
manifest = synthesizer.synthesis
# => { server: { web: { production: { host: 'api.example.com', ... } } } }
```

## 🔧 Core Concepts

### Resource Declaration
Resources are top-level methods in your DSL that accept multiple arguments for hierarchical nesting:

```ruby
# Basic resource with nested identifiers
server :web, :production do
  # Configuration fields go here
end

# Results in manifest structure:
# { server: { web: { production: { ... } } } }
```

### Field Assignment
Inside resource blocks, method calls without blocks become field assignments:

```ruby

# Define the allowed keys for your DSL
# These keys will be the valid methods you can call in your DSL block
resource_keys = %i[server database user]

synthesizer = SynthesizerFactory.create_synthesizer(name: :my_config, keys: resource_keys)

synthesizer.synthesize do
  server :web_server, :production do
    host 'example.com'
    port 8080
    ssl true
  end

  server :api_server, :development do
    host 'localhost'
    port 3000
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

# Access the generated manifest
puts synthesizer.synthesis.inspect
# Expected Output (simplified):
# {
#   :server => {
#     :web_server => {
#       :production => {
#         :host => "example.com", :port => 8080, :ssl => true
#       }
#     },
#     :api_server => {
#       :development => {
#         :host => "localhost", :port => 3000
#       }
#     }
#   },
#   :database => {
#     :main_db => {
#       :mysql => {
#         :username => "admin", :password => "secret", :host => "db.example.com"
#       }
#     }
#   },
#   :user => {
#     :admin_user => {
#       :name => "Administrator", :email => "admin@example.com"
#     }
#   }
# }
```

## DSL Structure

The DSL follows a hierarchical structure:

- **Resource Definition**: The top-level methods in your `synthesize` block correspond to the `keys` you provided to `create_synthesizer`. These methods can take multiple arguments, which become nested keys in the manifest.
  ```ruby
  resource_key :first_level_identifier, :second_level_identifier do
    # ... fields or nested resources
  end
  ```

- **Field Assignment**: Inside a resource block, methods without a block are treated as field assignments. They take a single argument, which is the value for that field.
  ```ruby
  field_name 'field_value'
  another_field 123
  ```

## Error Handling

The gem provides specific error classes for common issues:

- `InvalidSynthesizerKeyError`: Raised when you try to use a method in your DSL that was not included in the `keys` provided to `SynthesizerFactory.create_synthesizer`.
- `TooManyFieldValuesError`: Raised when a field assignment method receives more than one argument.

## 🎨 Creating DSLs

### Basic DSL Wrapper Pattern

```ruby
class MyConfigDSL
  def self.build(&block)
    # Define your domain's resource types
    resource_keys = %i[server database cache service]
    
    synthesizer = SynthesizerFactory.create_synthesizer(
      name: :my_config,
      keys: resource_keys
    )
    
    synthesizer.synthesize(&block)
    
    # Return wrapped instance with additional methods
    new(synthesizer.synthesis)
  end
  
  def initialize(manifest)
    @manifest = manifest
  end
  
  def to_yaml
    @manifest.to_yaml
  end
  
  def validate
    errors = []
    # Add your validation logic
    { valid: errors.empty?, errors: errors }
  end
end
```

### Multi-Environment DSLs

```ruby
class EnvironmentConfig
  def self.build(environment: :development, &block)
    resource_keys = %i[database cache service]
    
    synthesizer = SynthesizerFactory.create_synthesizer(
      name: :env_config,
      keys: resource_keys
    )
    
    # Add environment awareness
    synthesizer.define_singleton_method(:env) { environment }
    synthesizer.define_singleton_method(:production?) { environment == :production }
    
    synthesizer.synthesize(&block)
    new(synthesizer.synthesis, environment)
  end
end

# Usage
prod_config = EnvironmentConfig.build(environment: :production) do
  database :primary, :postgresql do
    host production? ? 'prod-db.com' : 'dev-db.com'
    ssl production? ? true : false
  end
end
```

## ✅ Validation Patterns

### Resource-Level Validation

```ruby
def validate_manifest(manifest)
  errors = []
  
  manifest.each do |resource_type, resources|
    case resource_type
    when :server
      resources.each do |server_name, variants|
        variants.each do |variant, config|
          errors << "#{server_name}.#{variant}: missing host" unless config[:host]
          errors << "#{server_name}.#{variant}: invalid port" if config[:port] && !config[:port].is_a?(Integer)
        end
      end
    when :database  
      resources.each do |db_name, variants|
        variants.each do |variant, config|
          errors << "#{db_name}.#{variant}: missing connection string" unless config[:host] || config[:url]
        end
      end
    end
  end
  
  { valid: errors.empty?, errors: errors }
end
```

### Field-Level Validation

```ruby
class ValidatedConfig
  VALID_PORTS = (1..65535).freeze
  REQUIRED_DB_FIELDS = %i[host port database].freeze
  
  def validate_server_config(name, config)
    errors = []
    errors << "#{name}: invalid port range" unless VALID_PORTS.include?(config[:port])
    errors << "#{name}: host required" if config[:host].nil? || config[:host].empty?
    errors
  end
  
  def validate_database_config(name, config)
    errors = []
    REQUIRED_DB_FIELDS.each do |field|
      errors << "#{name}: #{field} is required" unless config[field]
    end
    errors
  end
end
```

## 🔍 Error Handling

Abstract Synthesizer provides specific error classes for common issues:

### InvalidSynthesizerKeyError
Thrown when using undefined resource keys:

```ruby
synthesizer = SynthesizerFactory.create_synthesizer(
  name: :config,
  keys: %i[server database]  # Only these are allowed
)

synthesizer.synthesize do
  cache :redis do  # ❌ InvalidSynthesizerKeyError - 'cache' not in keys
    host 'localhost'
  end
end
```

### TooManyFieldValuesError
Thrown when field assignments receive multiple values:

```ruby
synthesizer.synthesize do
  server :web do
    port 8080, 3000  # ❌ TooManyFieldValuesError - fields accept only one value
  end
end
```

## 🚀 Advanced Patterns

### Conditional Configuration

```ruby
synthesizer = SynthesizerFactory.create_synthesizer(
  name: :conditional_config,
  keys: %i[server database cache]
)

# Add helper methods
synthesizer.define_singleton_method(:staging?) { ENV['RAILS_ENV'] == 'staging' }
synthesizer.define_singleton_method(:production?) { ENV['RAILS_ENV'] == 'production' }

synthesizer.synthesize do
  server :web, :app do
    host production? ? 'api.example.com' : 'localhost'
    port production? ? 443 : 3000
    ssl production?
  end
  
  database :primary, :postgresql do
    connection_pool production? ? 20 : 5
    query_timeout production? ? 30 : 60
  end
end
```

### Nested Configuration Blocks

```ruby
synthesizer.synthesize do
  server :web, :production do
    host 'api.example.com'
    port 443
    
    # Nested configuration (requires additional implementation)
    ssl_config do
      certificate_path '/etc/ssl/cert.pem'
      private_key_path '/etc/ssl/private.key'
      protocols ['TLSv1.2', 'TLSv1.3']
    end
    
    load_balancer do
      algorithm 'round_robin'
      health_check_path '/health'
      timeout 10
    end
  end
end
```

### Configuration Inheritance

```ruby
class InheritableConfig
  def self.build_with_defaults(defaults: {}, &block)
    config = build(&block)
    merged_manifest = deep_merge(defaults, config.manifest)
    new(merged_manifest)
  end
  
  private
  
  def self.deep_merge(default_hash, override_hash)
    default_hash.merge(override_hash) do |key, default_val, override_val|
      if default_val.is_a?(Hash) && override_val.is_a?(Hash)
        deep_merge(default_val, override_val)
      else
        override_val
      end
    end
  end
end
```

## 💡 Best Practices

### 1. **Design Your Domain Vocabulary First**
```ruby
# ✅ Good - Clear, domain-specific resource types
deployment_keys = %i[service deployment ingress configmap secret]

# ❌ Avoid - Generic or unclear resource types  
generic_keys = %i[thing item object resource]
```

### 2. **Provide Clear Validation Messages**
```ruby
# ✅ Good - Specific, actionable error messages
"server.web.production: port must be between 1 and 65535, got #{port}"

# ❌ Avoid - Vague error messages
"validation failed"
```

### 3. **Use Environment-Aware Configuration**
```ruby
# ✅ Good - Environment-specific behavior
synthesizer.define_singleton_method(:production?) { ENV['RAILS_ENV'] == 'production' }

synthesizer.synthesize do
  database :primary, :postgresql do
    ssl production? ? 'require' : 'prefer'
    connection_pool production? ? 20 : 5
  end
end
```

### 4. **Create Composable DSL Components**
```ruby
# ✅ Good - Reusable configuration components
class DatabaseConfig
  def self.postgres_defaults
    {
      port: 5432,
      ssl_mode: 'require',
      connection_pool: 10
    }
  end
end

config.synthesize do
  database :primary, :postgresql do
    DatabaseConfig.postgres_defaults.each { |k, v| send(k, v) }
    host 'custom-host.com'  # Override specific values
  end
end
```

### 5. **Implement Multiple Output Formats**
```ruby
class MyConfig
  def to_env_file
    # Convert to .env format
  end
  
  def to_yaml
    # Convert to YAML
  end
  
  def to_kubernetes_manifest
    # Convert to Kubernetes YAML
  end
end
```

---

## 🔗 Related Documentation

- **[Overview](overview.md)** - Architecture and technical implementation details
- **[Examples](../examples/)** - Complete real-world examples with full implementations  
- **[Main README](../README.md)** - Project overview and quick start guide

## 💡 Next Steps

1. Explore the [Examples](../examples/) to see these patterns in action
2. Read the [Architecture Overview](overview.md) to understand the internals
3. Start building your own DSL using these patterns!

