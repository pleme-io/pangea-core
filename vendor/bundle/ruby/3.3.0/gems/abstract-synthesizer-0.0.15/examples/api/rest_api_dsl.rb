#!/usr/bin/env ruby
# frozen_string_literal: true

require 'abstract-synthesizer'
require 'json'

# Example: REST API Configuration DSL
# This demonstrates how abstract-synthesizer can create a declarative
# language for API definition with automatic route generation and validation.

class RestAPIConfiguration
  def self.build(&block)
    api_resources = %i[namespace resource middleware auth]
    
    synthesizer = SynthesizerFactory.create_synthesizer(
      name: :rest_api_config,
      keys: api_resources
    )
    
    synthesizer.synthesize(&block)
    
    new(synthesizer.synthesis)
  end
  
  def initialize(manifest)
    @manifest = manifest
  end
  
  def to_rails_routes
    routes = []
    routes << "Rails.application.routes.draw do"
    
    @manifest.each do |resource_type, resources|
      case resource_type
      when :namespace
        routes.concat(generate_namespace_routes(resources))
      when :resource
        routes.concat(generate_resource_routes(resources))
      end
    end
    
    routes << "end"
    routes.join("\n")
  end
  
  def to_openapi
    {
      openapi: "3.0.0",
      info: {
        title: "Generated API",
        version: "1.0.0"
      },
      paths: generate_openapi_paths
    }
  end
  
  def verify_manifest
    errors = []
    
    @manifest.each do |resource_type, resources|
      case resource_type
      when :resource
        resources.each do |resource_name, config|
          config.each do |action, settings|
            next unless %i[get post put delete patch].include?(action)
            
            if settings[:auth] && !has_auth_middleware?
              errors << "#{resource_name}.#{action}: requires auth but no auth middleware defined"
            end
            
            if settings[:validation] && !valid_schema?(settings[:validation])
              errors << "#{resource_name}.#{action}: invalid validation schema"
            end
          end
        end
      end
    end
    
    { valid: errors.empty?, errors: errors }
  end
  
  private
  
  def generate_namespace_routes(namespaces)
    routes = []
    
    namespaces.each do |namespace_name, versions|
      versions.each do |version, config|
        routes << "  namespace :#{namespace_name} do"
        routes << "    namespace :#{version} do"
        
        if config[:middleware]
          Array(config[:middleware]).each do |middleware|
            routes << "      # Middleware: #{middleware}"
          end
        end
        
        if config[:resource]
          config[:resource].each do |resource_name, resource_config|
            routes << "      resources :#{resource_name} do"
            
            resource_config.each do |action, settings|
              next unless %i[get post put delete patch].include?(action)
              
              auth_comment = settings[:auth] ? " # Requires authentication" : ""
              cache_comment = settings[:cache] ? " # Cached for #{settings[:cache]}s" : ""
              
              routes << "        #{action} :#{action == :get ? 'index' : action}#{auth_comment}#{cache_comment}"
            end
            
            routes << "      end"
          end
        end
        
        routes << "    end"
        routes << "  end"
      end
    end
    
    routes
  end
  
  def generate_resource_routes(resources)
    routes = []
    
    resources.each do |resource_name, config|
      routes << "  resources :#{resource_name} do"
      
      config.each do |action, settings|
        next unless %i[get post put delete patch].include?(action)
        
        auth_comment = settings[:auth] ? " # Requires authentication" : ""
        routes << "    #{action} :#{action}#{auth_comment}"
      end
      
      routes << "  end"
    end
    
    routes
  end
  
  def generate_openapi_paths
    paths = {}
    
    @manifest.each do |resource_type, resources|
      case resource_type
      when :namespace
        resources.each do |namespace_name, versions|
          versions.each do |version, config|
            next unless config[:resource]
            
            config[:resource].each do |resource_name, resource_config|
              path_base = "/#{namespace_name}/#{version}/#{resource_name}"
              
              resource_config.each do |action, settings|
                next unless %i[get post put delete patch].include?(action)
                
                path = action == :get ? path_base : "#{path_base}/{id}"
                paths[path] ||= {}
                
                paths[path][action.to_s] = {
                  summary: "#{action.to_s.capitalize} #{resource_name}",
                  security: settings[:auth] ? [{ bearerAuth: [] }] : nil,
                  responses: generate_responses_for_action(action)
                }.compact
              end
            end
          end
        end
      end
    end
    
    paths
  end
  
  def generate_responses_for_action(action)
    case action
    when :get
      {
        "200" => { description: "Success" },
        "404" => { description: "Not found" }
      }
    when :post
      {
        "201" => { description: "Created" },
        "400" => { description: "Bad request" }
      }
    when :put, :patch
      {
        "200" => { description: "Updated" },
        "404" => { description: "Not found" }
      }
    when :delete
      {
        "204" => { description: "Deleted" },
        "404" => { description: "Not found" }
      }
    end
  end
  
  def has_auth_middleware?
    @manifest.dig(:middleware, :auth) || 
    @manifest.values.any? { |v| v.is_a?(Hash) && v.values.any? { |vv| vv.is_a?(Hash) && vv[:middleware]&.include?(:authentication) } }
  end
  
  def valid_schema?(schema)
    schema.is_a?(Symbol) || schema.is_a?(String)
  end
end

# Usage Example
if __FILE__ == $0
  api_config = RestAPIConfiguration.build do
    namespace :api, :v1 do
      middleware :authentication
      middleware :rate_limiting, requests: 1000, window: 3600
      middleware :cors
      
      resource :users do
        get :index, auth: true, cache: 300
        get :show, auth: true, cache: 600
        post :create, validation: :UserCreateSchema
        put :update, auth: true, validation: :UserUpdateSchema
        delete :destroy, auth: true, admin_only: true
      end
      
      resource :posts do
        get :index, cache: 300, pagination: true
        get :show, cache: 600
        post :create, auth: true, validation: :PostCreateSchema
        put :update, auth: true, validation: :PostUpdateSchema
        delete :destroy, auth: true
      end
      
      resource :comments do
        get :index, cache: 120
        post :create, auth: true, validation: :CommentSchema
        delete :destroy, auth: true
      end
    end
    
    auth :jwt do
      secret ENV['JWT_SECRET']
      expiry 3600
      refresh_token true
    end
    
    middleware :global do
      cors_enabled true
      rate_limiting 10000
      request_logging true
    end
  end
  
  # Verify the API configuration
  verification = api_config.verify_manifest
  if verification[:valid]
    puts "✅ API configuration is valid"
    
    puts "\n--- Generated Rails Routes ---"
    puts api_config.to_rails_routes
    
    puts "\n--- Generated OpenAPI Specification ---"
    puts JSON.pretty_generate(api_config.to_openapi)
  else
    puts "❌ API configuration errors:"
    verification[:errors].each { |error| puts "  - #{error}" }
  end
end