#!/usr/bin/env ruby
# frozen_string_literal: true

require 'abstract-synthesizer'
require 'yaml'

# Example: Kubernetes Infrastructure DSL
# This demonstrates how abstract-synthesizer can create domain-specific
# languages for infrastructure definition with built-in validation.

class KubernetesInfrastructure
  def self.build(&block)
    # Define Kubernetes resource types
    k8s_resources = %i[deployment service configmap secret ingress]
    
    synthesizer = SynthesizerFactory.create_synthesizer(
      name: :kubernetes_infrastructure,
      keys: k8s_resources
    )
    
    synthesizer.synthesize(&block)
    
    # Convert to verifiable manifest
    new(synthesizer.synthesis)
  end
  
  def initialize(manifest)
    @manifest = manifest
  end
  
  def to_kubernetes_yaml
    resources = []
    
    @manifest.each do |resource_type, resources_data|
      resources_data.each do |resource_name, variants|
        variants.each do |variant_name, config|
          resources << build_k8s_resource(resource_type, resource_name, variant_name, config)
        end
      end
    end
    
    resources.map(&:to_yaml).join("---\n")
  end
  
  def verify_manifest
    errors = []
    
    # Verify required fields exist
    @manifest.each do |resource_type, resources_data|
      resources_data.each do |resource_name, variants|
        variants.each do |variant_name, config|
          case resource_type
          when :deployment
            errors << "#{resource_name}.#{variant_name}: missing image" unless config[:image]
            errors << "#{resource_name}.#{variant_name}: missing replicas" unless config[:replicas]
          when :service
            errors << "#{resource_name}.#{variant_name}: missing port" unless config[:port]
            errors << "#{resource_name}.#{variant_name}: missing target_port" unless config[:target_port]
          end
        end
      end
    end
    
    { valid: errors.empty?, errors: errors }
  end
  
  private
  
  def build_k8s_resource(type, name, variant, config)
    case type
    when :deployment
      {
        'apiVersion' => 'apps/v1',
        'kind' => 'Deployment',
        'metadata' => { 'name' => "#{name}-#{variant}" },
        'spec' => {
          'replicas' => config[:replicas],
          'selector' => { 'matchLabels' => { 'app' => name.to_s } },
          'template' => {
            'metadata' => { 'labels' => { 'app' => name.to_s } },
            'spec' => {
              'containers' => [{
                'name' => name.to_s,
                'image' => config[:image],
                'ports' => [{ 'containerPort' => config[:container_port] || 8080 }]
              }]
            }
          }
        }
      }
    when :service
      {
        'apiVersion' => 'v1',
        'kind' => 'Service',
        'metadata' => { 'name' => "#{name}-#{variant}-service" },
        'spec' => {
          'selector' => { 'app' => name.to_s },
          'ports' => [{
            'port' => config[:port],
            'targetPort' => config[:target_port]
          }]
        }
      }
    end
  end
end

# Usage Example
if __FILE__ == $0
  infrastructure = KubernetesInfrastructure.build do
    deployment :web_app, :production do
      image 'nginx:1.21'
      replicas 3
      container_port 80
    end
    
    deployment :web_app, :staging do
      image 'nginx:1.21-alpine'
      replicas 1
      container_port 80
    end
    
    service :web_app, :production do
      port 80
      target_port 80
      type 'LoadBalancer'
    end
    
    service :web_app, :staging do
      port 80
      target_port 80
      type 'ClusterIP'
    end
    
    configmap :app_config, :production do
      database_url 'postgres://prod-db:5432/app'
      redis_url 'redis://prod-redis:6379'
      log_level 'info'
    end
  end
  
  # Verify the configuration
  verification = infrastructure.verify_manifest
  if verification[:valid]
    puts "✅ Infrastructure configuration is valid"
    puts "\n--- Generated Kubernetes YAML ---"
    puts infrastructure.to_kubernetes_yaml
  else
    puts "❌ Configuration errors:"
    verification[:errors].each { |error| puts "  - #{error}" }
  end
end