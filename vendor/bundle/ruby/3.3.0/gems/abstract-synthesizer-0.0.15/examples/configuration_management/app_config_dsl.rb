#!/usr/bin/env ruby
# frozen_string_literal: true

require 'abstract-synthesizer'
require 'json'

# Example: Application Configuration Management DSL
# This demonstrates how abstract-synthesizer can create a powerful
# configuration management system with validation, environment-specific
# configs, and manifest verification for drift detection.

class ApplicationConfigurationManager
  def self.build(environment: :development, &block)
    config_resources = %i[database cache service logging security feature monitoring]
    
    synthesizer = SynthesizerFactory.create_synthesizer(
      name: :app_config,
      keys: config_resources
    )
    
    # Set environment context for conditional configuration
    synthesizer.instance_variable_set(:@environment, environment)
    synthesizer.define_singleton_method(:env) { @environment }
    synthesizer.define_singleton_method(:production?) { @environment == :production }
    synthesizer.define_singleton_method(:staging?) { @environment == :staging }
    synthesizer.define_singleton_method(:development?) { @environment == :development }
    
    synthesizer.synthesize(&block)
    
    new(synthesizer.synthesis, environment)
  end
  
  def initialize(manifest, environment)
    @manifest = manifest
    @environment = environment
  end
  
  def to_env_file
    env_vars = []
    env_vars << "# Generated configuration for #{@environment} environment"
    env_vars << "# Generated at: #{Time.now}"
    env_vars << ""
    
    flatten_manifest(@manifest).each do |key, value|
      env_key = key.upcase.gsub('/', '_').gsub('.', '_')
      env_vars << "#{env_key}=#{value}"
    end
    
    env_vars.join("\n")
  end
  
  def to_yaml
    require 'yaml'
    {
      @environment => @manifest
    }.to_yaml
  end
  
  def to_json
    JSON.pretty_generate({
      environment: @environment,
      generated_at: Time.now.iso8601,
      configuration: @manifest
    })
  end
  
  def verify_manifest
    errors = []
    warnings = []
    
    # Database validation
    if @manifest[:database]
      @manifest[:database].each do |db_name, db_types|
        db_types.each do |db_type, config|
          if config[:host].nil? || config[:host].empty?
            errors << "#{db_name}.#{db_type}: host is required"
          end
          
          if config[:password].nil? && @environment == :production
            errors << "#{db_name}.#{db_type}: password is required in production"
          end
          
          if config[:ssl] != true && @environment == :production
            warnings << "#{db_name}.#{db_type}: SSL should be enabled in production"
          end
          
          if config[:connection_pool] && config[:connection_pool] < 5
            warnings << "#{db_name}.#{db_type}: connection pool size is quite low (#{config[:connection_pool]})"
          end
        end
      end
    end
    
    # Cache validation
    if @manifest[:cache]
      @manifest[:cache].each do |cache_name, cache_types|
        cache_types.each do |cache_type, config|
          if config[:memory] && !config[:memory].match?(/\d+(MB|GB)/)
            errors << "#{cache_name}.#{cache_type}: invalid memory format (use MB or GB)"
          end
          
          if config[:eviction_policy].nil?
            warnings << "#{cache_name}.#{cache_type}: no eviction policy specified"
          end
        end
      end
    end
    
    # Security validation
    if @manifest[:security]
      @manifest[:security].each do |security_name, config|
        config.each do |setting_name, setting_config|
          if setting_name == :jwt && setting_config[:secret].nil?
            errors << "#{security_name}.jwt: secret is required"
          end
          
          if setting_name == :jwt && setting_config[:expiry] && setting_config[:expiry] > 86400 && @environment == :production
            warnings << "#{security_name}.jwt: token expiry is quite long for production (#{setting_config[:expiry]}s)"
          end
          
          if setting_name == :cors && setting_config[:origins] == '*' && @environment == :production
            errors << "#{security_name}.cors: wildcard origins not allowed in production"
          end
        end
      end
    end
    
    # Feature flags validation
    if @manifest[:feature]
      @manifest[:feature].each do |feature_name, config|
        config.each do |flag_name, flag_config|
          unless [true, false].include?(flag_config[:enabled])
            errors << "#{feature_name}.#{flag_name}: enabled must be true or false"
          end
          
          if flag_config[:rollout_percentage] && (flag_config[:rollout_percentage] < 0 || flag_config[:rollout_percentage] > 100)
            errors << "#{feature_name}.#{flag_name}: rollout_percentage must be between 0 and 100"
          end
        end
      end
    end
    
    {
      valid: errors.empty?,
      errors: errors,
      warnings: warnings,
      summary: {
        total_errors: errors.length,
        total_warnings: warnings.length,
        environment: @environment
      }
    }
  end
  
  def compare_with(other_config)
    other_manifest = other_config.is_a?(ApplicationConfigurationManager) ? 
                     other_config.instance_variable_get(:@manifest) : other_config
    
    differences = find_differences(@manifest, other_manifest)
    
    {
      has_differences: !differences.empty?,
      differences: differences,
      summary: {
        total_differences: differences.length,
        added_keys: differences.count { |d| d[:type] == :added },
        removed_keys: differences.count { |d| d[:type] == :removed },
        changed_values: differences.count { |d| d[:type] == :changed }
      }
    }
  end
  
  def generate_deployment_checklist
    checklist = []
    checklist << "# Deployment Checklist for #{@environment.capitalize} Environment"
    checklist << ""
    
    # Database checklist
    if @manifest[:database]
      checklist << "## Database Configuration"
      @manifest[:database].each do |db_name, db_types|
        db_types.each do |db_type, config|
          checklist << "- [ ] Verify #{db_name} #{db_type} database is accessible at #{config[:host]}"
          checklist << "- [ ] Confirm #{db_name} #{db_type} credentials are valid"
          checklist << "- [ ] Test connection pool size (#{config[:connection_pool] || 'default'})"
          checklist << "- [ ] Verify SSL configuration" if config[:ssl]
        end
      end
      checklist << ""
    end
    
    # Service checklist
    if @manifest[:service]
      checklist << "## External Services"
      @manifest[:service].each do |service_name, service_types|
        service_types.each do |service_type, config|
          checklist << "- [ ] Verify #{service_name} #{service_type} is reachable at #{config[:endpoint]}"
          checklist << "- [ ] Test API key/authentication for #{service_name} #{service_type}"
          checklist << "- [ ] Confirm rate limits and quotas"
        end
      end
      checklist << ""
    end
    
    # Security checklist
    if @manifest[:security]
      checklist << "## Security Configuration"
      checklist << "- [ ] Verify all secrets are properly set"
      checklist << "- [ ] Confirm JWT secret is rotated if needed"
      checklist << "- [ ] Test CORS configuration"
      checklist << "- [ ] Verify rate limiting is working"
      checklist << ""
    end
    
    # Feature flags checklist
    if @manifest[:feature]
      checklist << "## Feature Flags"
      @manifest[:feature].each do |feature_name, config|
        config.each do |flag_name, flag_config|
          status = flag_config[:enabled] ? "ENABLED" : "DISABLED"
          checklist << "- [ ] Confirm #{feature_name}.#{flag_name} is #{status}"
          if flag_config[:rollout_percentage]
            checklist << "- [ ] Verify rollout percentage for #{feature_name}.#{flag_name} (#{flag_config[:rollout_percentage]}%)"
          end
        end
      end
      checklist << ""
    end
    
    checklist << "## Final Steps"
    checklist << "- [ ] All configuration validation tests pass"
    checklist << "- [ ] Environment-specific smoke tests complete"
    checklist << "- [ ] Monitoring alerts are configured"
    checklist << "- [ ] Rollback plan is ready"
    
    checklist.join("\n")
  end
  
  private
  
  def flatten_manifest(hash, prefix = nil)
    flattened = {}
    
    hash.each do |key, value|
      new_key = prefix ? "#{prefix}/#{key}" : key.to_s
      
      if value.is_a?(Hash)
        flattened.merge!(flatten_manifest(value, new_key))
      else
        flattened[new_key] = value
      end
    end
    
    flattened
  end
  
  def find_differences(hash1, hash2, path = [])
    differences = []
    
    all_keys = (hash1.keys + hash2.keys).uniq
    
    all_keys.each do |key|
      current_path = path + [key]
      path_string = current_path.join('.')
      
      if !hash1.key?(key)
        differences << {
          type: :added,
          path: path_string,
          value: hash2[key]
        }
      elsif !hash2.key?(key)
        differences << {
          type: :removed,
          path: path_string,
          value: hash1[key]
        }
      elsif hash1[key].is_a?(Hash) && hash2[key].is_a?(Hash)
        differences.concat(find_differences(hash1[key], hash2[key], current_path))
      elsif hash1[key] != hash2[key]
        differences << {
          type: :changed,
          path: path_string,
          old_value: hash1[key],
          new_value: hash2[key]
        }
      end
    end
    
    differences
  end
end

# Usage Example
if __FILE__ == $0
  # Production Configuration
  production_config = ApplicationConfigurationManager.build(environment: :production) do
    database :primary, :postgresql do
      host ENV['PROD_DB_HOST'] || 'prod-db.company.com'
      port 5432
      database 'myapp_production'
      username 'myapp'
      password ENV['PROD_DB_PASSWORD']
      ssl true
      connection_pool 20
      query_timeout 30
    end
    
    database :readonly, :postgresql do
      host ENV['PROD_RO_DB_HOST'] || 'prod-db-readonly.company.com'
      port 5432
      database 'myapp_production'
      username 'myapp_readonly'
      password ENV['PROD_RO_DB_PASSWORD']
      ssl true
      connection_pool 10
    end
    
    cache :redis, :primary do
      host ENV['PROD_REDIS_HOST'] || 'prod-redis.company.com'
      port 6379
      password ENV['PROD_REDIS_PASSWORD']
      memory '2GB'
      eviction_policy 'allkeys-lru'
      persistence true
      cluster_mode true
    end
    
    service :payment_gateway, :stripe do
      endpoint 'https://api.stripe.com'
      api_key ENV['STRIPE_API_KEY']
      webhook_secret ENV['STRIPE_WEBHOOK_SECRET']
      timeout 10
      retries 3
    end
    
    service :email_service, :sendgrid do
      endpoint 'https://api.sendgrid.com'
      api_key ENV['SENDGRID_API_KEY']
      from_email 'noreply@company.com'
      timeout 5
    end
    
    logging :application, :structured do
      level 'info'
      format 'json'
      destination 'stdout'
      include_metadata true
    end
    
    logging :audit, :compliance do
      level 'info'
      destination 'splunk'
      retention_days 365
      encryption true
    end
    
    security :authentication, :jwt do
      secret ENV['JWT_SECRET']
      expiry 3600
      refresh_enabled true
      algorithm 'HS256'
    end
    
    security :web, :cors do
      origins ['https://app.company.com', 'https://admin.company.com']
      credentials true
      max_age 86400
    end
    
    security :api, :rate_limiting do
      requests_per_minute 1000
      burst_limit 100
      ip_whitelist ['10.0.0.0/8']
    end
    
    feature :new_ui, :beta do
      enabled true
      rollout_percentage 25
      target_users ['beta_testers']
    end
    
    feature :advanced_analytics, :premium do
      enabled true
      rollout_percentage 100
      required_plan 'premium'
    end
    
    monitoring :apm, :datadog do
      api_key ENV['DATADOG_API_KEY']
      service_name 'myapp-production'
      trace_sampling 0.1
      log_correlation true
    end
    
    monitoring :metrics, :prometheus do
      endpoint '/metrics'
      scrape_interval 30
      retention_days 90
    end
  end
  
  # Verify the configuration
  verification = production_config.verify_manifest
  
  puts "🔍 Configuration Verification Results"
  puts "=" * 50
  
  if verification[:valid]
    puts "✅ Configuration is valid!"
  else
    puts "❌ Configuration has errors:"
    verification[:errors].each { |error| puts "  - #{error}" }
  end
  
  unless verification[:warnings].empty?
    puts "\n⚠️  Warnings:"
    verification[:warnings].each { |warning| puts "  - #{warning}" }
  end
  
  puts "\n📊 Summary:"
  puts "  - Environment: #{verification[:summary][:environment]}"
  puts "  - Errors: #{verification[:summary][:total_errors]}"
  puts "  - Warnings: #{verification[:summary][:total_warnings]}"
  
  if verification[:valid]
    puts "\n📝 Generated Configuration Files:"
    puts "\n--- .env.production ---"
    puts production_config.to_env_file
    
    puts "\n--- config/production.yml ---"
    puts production_config.to_yaml
    
    puts "\n📋 Deployment Checklist:"
    puts production_config.generate_deployment_checklist
  end
end