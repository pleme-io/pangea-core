#!/usr/bin/env ruby
# frozen_string_literal: true

require 'abstract-synthesizer'
require 'yaml'

# Example: CI/CD Pipeline Configuration DSL
# This demonstrates how abstract-synthesizer can create a declarative
# language for build pipelines with automatic CI/CD generation.

class CICDPipelineConfiguration
  def self.build(&block)
    pipeline_resources = %i[pipeline stage task trigger notification artifact]
    
    synthesizer = SynthesizerFactory.create_synthesizer(
      name: :cicd_pipeline,
      keys: pipeline_resources
    )
    
    synthesizer.synthesize(&block)
    
    new(synthesizer.synthesis)
  end
  
  def initialize(manifest)
    @manifest = manifest
  end
  
  def to_github_actions
    workflows = {}
    
    @manifest.each do |resource_type, resources|
      next unless resource_type == :pipeline
      
      resources.each do |pipeline_name, variants|
        variants.each do |variant, config|
          workflow_name = "#{pipeline_name}_#{variant}"
          workflows[workflow_name] = generate_github_workflow(pipeline_name, config)
        end
      end
    end
    
    workflows
  end
  
  def to_gitlab_ci
    gitlab_configs = {}
    
    @manifest.each do |resource_type, resources|
      next unless resource_type == :pipeline
      
      resources.each do |pipeline_name, variants|
        variants.each do |variant, config|
          config_name = "#{pipeline_name}_#{variant}"
          gitlab_configs[config_name] = generate_gitlab_config(config)
        end
      end
    end
    
    gitlab_configs
  end
  
  def to_jenkinsfile
    jenkinsfiles = {}
    
    @manifest.each do |resource_type, resources|
      next unless resource_type == :pipeline
      
      resources.each do |pipeline_name, variants|
        variants.each do |variant, config|
          file_name = "Jenkinsfile.#{pipeline_name}.#{variant}"
          jenkinsfiles[file_name] = generate_jenkinsfile(config)
        end
      end
    end
    
    jenkinsfiles
  end
  
  def verify_manifest
    errors = []
    
    @manifest.each do |resource_type, resources|
      case resource_type
      when :pipeline
        resources.each do |pipeline_name, variants|
          variants.each do |variant, config|
            # Check for required stages
            unless config[:stage]
              errors << "#{pipeline_name}.#{variant}: no stages defined"
              next
            end
            
            # Validate stage dependencies
            stages = config[:stage]
            stages.each do |stage_name, stage_config|
              next unless stage_config[:depends_on]
              
              dependency = stage_config[:depends_on]
              unless stages.key?(dependency)
                errors << "#{pipeline_name}.#{variant}.#{stage_name}: depends on non-existent stage '#{dependency}'"
              end
            end
            
            # Check for tasks in stages
            stages.each do |stage_name, stage_config|
              unless stage_config[:task]
                errors << "#{pipeline_name}.#{variant}.#{stage_name}: no tasks defined"
              end
            end
          end
        end
      when :trigger
        resources.each do |trigger_name, config|
          config.each do |condition, settings|
            unless %i[push pull_request schedule manual].include?(condition)
              errors << "#{trigger_name}: unsupported trigger condition '#{condition}'"
            end
          end
        end
      end
    end
    
    { valid: errors.empty?, errors: errors }
  end
  
  private
  
  def generate_github_workflow(pipeline_name, config)
    workflow = {
      'name' => pipeline_name.to_s.gsub('_', ' ').capitalize,
      'on' => generate_github_triggers(config),
      'jobs' => {}
    }
    
    return workflow unless config[:stage]
    
    # Generate jobs for each stage
    config[:stage].each do |stage_name, stage_config|
      job = {
        'runs-on' => stage_config[:runner] || 'ubuntu-latest',
        'steps' => []
      }
      
      # Add checkout step
      job['steps'] << {
        'name' => 'Checkout code',
        'uses' => 'actions/checkout@v3'
      }
      
      # Add dependency
      if stage_config[:depends_on]
        job['needs'] = [stage_config[:depends_on].to_s]
      end
      
      # Add tasks as steps
      if stage_config[:task]
        stage_config[:task].each do |task_name, task_config|
          step = {
            'name' => task_name.to_s.gsub('_', ' ').capitalize,
            'run' => task_config[:command]
          }
          
          # Add conditional execution
          if task_config[:condition]
            step['if'] = convert_condition_to_github(task_config[:condition])
          end
          
          job['steps'] << step
        end
      end
      
      workflow['jobs'][stage_name.to_s] = job
    end
    
    workflow
  end
  
  def generate_gitlab_config(config)
    gitlab_config = {
      'stages' => [],
      'variables' => {}
    }
    
    return gitlab_config unless config[:stage]
    
    # Extract stage names
    gitlab_config['stages'] = config[:stage].keys.map(&:to_s)
    
    # Generate jobs for each stage
    config[:stage].each do |stage_name, stage_config|
      next unless stage_config[:task]
      
      stage_config[:task].each do |task_name, task_config|
        job_name = "#{stage_name}_#{task_name}"
        
        job = {
          'stage' => stage_name.to_s,
          'script' => [task_config[:command]]
        }
        
        # Add conditional execution
        if task_config[:condition]
          job['rules'] = [{ 'if' => convert_condition_to_gitlab(task_config[:condition]) }]
        end
        
        # Add image if specified
        if stage_config[:image]
          job['image'] = stage_config[:image]
        end
        
        gitlab_config[job_name] = job
      end
    end
    
    gitlab_config
  end
  
  def generate_jenkinsfile(config)
    jenkinsfile = ["pipeline {"]
    jenkinsfile << "  agent any"
    jenkinsfile << ""
    
    if config[:stage]
      jenkinsfile << "  stages {"
      
      config[:stage].each do |stage_name, stage_config|
        jenkinsfile << "    stage('#{stage_name.to_s.capitalize}') {"
        jenkinsfile << "      steps {"
        
        if stage_config[:task]
          stage_config[:task].each do |task_name, task_config|
            command = task_config[:command]
            
            if task_config[:condition]
              jenkinsfile << "        script {"
              jenkinsfile << "          if (#{convert_condition_to_jenkins(task_config[:condition])}) {"
              jenkinsfile << "            sh '#{command}'"
              jenkinsfile << "          }"
              jenkinsfile << "        }"
            else
              jenkinsfile << "        sh '#{command}'"
            end
          end
        end
        
        jenkinsfile << "      }"
        jenkinsfile << "    }"
      end
      
      jenkinsfile << "  }"
    end
    
    # Add notifications
    if config[:notification]
      jenkinsfile << ""
      jenkinsfile << "  post {"
      
      config[:notification].each do |event, settings|
        case event
        when :failure
          jenkinsfile << "    failure {"
          jenkinsfile << "      emailext subject: 'Build Failed: ${env.JOB_NAME} - ${env.BUILD_NUMBER}',"
          jenkinsfile << "               body: 'Build failed. Check console output.',"
          jenkinsfile << "               to: '#{settings[:email]}'"
          jenkinsfile << "    }"
        when :success
          jenkinsfile << "    success {"
          jenkinsfile << "      emailext subject: 'Build Successful: ${env.JOB_NAME} - ${env.BUILD_NUMBER}',"
          jenkinsfile << "               body: 'Build completed successfully.',"
          jenkinsfile << "               to: '#{settings[:email]}'"
          jenkinsfile << "    }"
        end
      end
      
      jenkinsfile << "  }"
    end
    
    jenkinsfile << "}"
    jenkinsfile.join("\n")
  end
  
  def generate_github_triggers(config)
    triggers = {}
    
    # Default to push if no triggers specified
    return { 'push' => { 'branches' => ['main'] } } unless config[:trigger]
    
    config[:trigger].each do |trigger_name, trigger_config|
      trigger_config.each do |condition, settings|
        case condition
        when :push
          triggers['push'] = { 'branches' => Array(settings[:branches] || 'main') }
        when :pull_request
          triggers['pull_request'] = { 'branches' => Array(settings[:branches] || 'main') }
        when :schedule
          triggers['schedule'] = [{ 'cron' => settings[:cron] }]
        when :manual
          triggers['workflow_dispatch'] = {}
        end
      end
    end
    
    triggers
  end
  
  def convert_condition_to_github(condition)
    case condition
    when /branch == (\w+)/
      "github.ref == 'refs/heads/#{$1}'"
    when /tag == (\w+)/
      "startsWith(github.ref, 'refs/tags/#{$1}')"
    else
      condition
    end
  end
  
  def convert_condition_to_gitlab(condition)
    case condition
    when /branch == (\w+)/
      "$CI_COMMIT_REF_NAME == '#{$1}'"
    when /tag == (\w+)/
      "$CI_COMMIT_TAG =~ /^#{$1}/"
    else
      condition
    end
  end
  
  def convert_condition_to_jenkins(condition)
    case condition
    when /branch == (\w+)/
      "env.BRANCH_NAME == '#{$1}'"
    when /tag == (\w+)/
      "env.TAG_NAME?.startsWith('#{$1}')"
    else
      condition
    end
  end
end

# Usage Example
if __FILE__ == $0
  pipeline_config = CICDPipelineConfiguration.build do
    pipeline :web_app, :ci do
      trigger :main_pipeline do
        push branches: %w[main develop]
        pull_request branches: ['main']
        schedule cron: '0 2 * * *'
      end
      
      stage :test do
        runner 'ubuntu-latest'
        
        task :unit_tests do
          command 'bundle exec rspec'
        end
        
        task :integration_tests do
          command 'bundle exec cucumber'
        end
        
        task :lint do
          command 'bundle exec rubocop'
        end
        
        task :security_scan do
          command 'bundle exec brakeman'
        end
      end
      
      stage :build, depends_on: :test do
        task :compile_assets do
          command 'bundle exec rake assets:precompile'
        end
        
        task :build_docker_image do
          command 'docker build -t myapp:${BUILD_ID} .'
        end
        
        task :run_smoke_tests do
          command 'docker run --rm myapp:${BUILD_ID} bundle exec rake smoke_tests'
        end
      end
      
      stage :deploy, depends_on: :build do
        task :deploy_staging do
          command 'kubectl apply -f k8s/staging/ && kubectl rollout status deployment/web-app-staging'
          condition 'branch == develop'
        end
        
        task :deploy_production do
          command 'kubectl apply -f k8s/production/ && kubectl rollout status deployment/web-app-production'
          condition 'branch == main'
        end
      end
      
      notification :pipeline_complete do
        failure email: 'devops@company.com', slack: '#deployments'
        success email: 'team@company.com'
      end
    end
    
    artifact :build_artifacts do
      docker_image 'myapp:${BUILD_ID}'
      test_reports 'spec/reports/**/*.xml'
      coverage_report 'coverage/lcov.info'
      retention_days 30
    end
  end
  
  # Verify the pipeline configuration
  verification = pipeline_config.verify_manifest
  if verification[:valid]
    puts "✅ Pipeline configuration is valid"
    
    puts "\n--- Generated GitHub Actions Workflow ---"
    github_workflows = pipeline_config.to_github_actions
    github_workflows.each do |name, workflow|
      puts "## #{name}.yml"
      puts YAML.dump(workflow)
      puts
    end
    
    puts "\n--- Generated GitLab CI Configuration ---"
    gitlab_configs = pipeline_config.to_gitlab_ci
    gitlab_configs.each do |name, config|
      puts "## .gitlab-ci-#{name}.yml"
      puts YAML.dump(config)
      puts
    end
    
    puts "\n--- Generated Jenkinsfile ---"
    jenkinsfiles = pipeline_config.to_jenkinsfile
    jenkinsfiles.each do |name, content|
      puts "## #{name}"
      puts content
      puts
    end
  else
    puts "❌ Pipeline configuration errors:"
    verification[:errors].each { |error| puts "  - #{error}" }
  end
end