# frozen_string_literal: true

require_relative '../magma'

module Pangea
  module Magma
    # RSpec custom matchers for "this workspace works under magma".
    #
    # # Usage
    #
    #   require 'pangea/magma/matchers'
    #
    #   RSpec.describe 'seph-vpc workspace' do
    #     it 'plans cleanly under magma' do
    #       expect('workspaces/seph-vpc').to plan_cleanly_under_magma
    #     end
    #
    #     it 'declares the expected providers' do
    #       expect('workspaces/seph-vpc').to plan_cleanly_under_magma
    #         .with_provider('hashicorp/aws')
    #     end
    #
    #     it 'emits at least 3 resource changes' do
    #       expect('workspaces/seph-vpc').to plan_cleanly_under_magma
    #         .with_at_least(3).resource_changes
    #     end
    #
    #     it 'is compatible with magma backend' do
    #       expect('workspaces/seph-vpc').to be_compatible_with_backend('magma')
    #     end
    #   end
    #
    # All matchers skip-with-print when magma isn't installed so CI on
    # machines without the magma binary doesn't fail hard.
    module Matchers
      class PlanCleanlyUnderMagma
        def initialize
          @required_providers = []
          @min_resource_changes = nil
          @resource_types = []
        end

        # @return self — chains: `with_provider('hashicorp/aws')`
        def with_provider(source)
          @required_providers << source
          self
        end

        # Alias to read more naturally before `.resource_changes`
        def with_at_least(n)
          @min_resource_changes = n
          self
        end

        # No-op terminator — lets the chain read
        # `.with_at_least(3).resource_changes` naturally.
        def resource_changes
          self
        end

        # @return self — chains: `with_resource_type('aws_vpc')`
        def with_resource_type(type)
          @resource_types << type
          self
        end

        def matches?(workspace_path)
          unless Pangea::Magma.installed?
            @failure_message = "magma binary not installed (set MAGMA_BINARY or install)"
            return false
          end
          @report = Pangea::Magma.verify_workspace(workspace_path)

          unless @report.dig('compatibility', 'plans_cleanly')
            @failure_message = "workspace #{workspace_path} did not plan cleanly: #{@report.inspect}"
            return false
          end

          @required_providers.each do |source|
            unless Array(@report['providers']).include?(source)
              @failure_message = "expected provider #{source.inspect}; got #{@report['providers']}"
              return false
            end
          end

          if @min_resource_changes
            actual = @report['resource_change_count'].to_i
            if actual < @min_resource_changes
              @failure_message = "expected ≥#{@min_resource_changes} resource changes; got #{actual}"
              return false
            end
          end

          @resource_types.each do |type|
            unless Array(@report['resource_types']).include?(type)
              @failure_message = "expected resource type #{type.inspect}; got #{@report['resource_types']}"
              return false
            end
          end
          true
        rescue Pangea::Magma::VerificationFailed => e
          @failure_message = "magma fixture verify raised: #{e.message}"
          false
        end

        def failure_message
          @failure_message || "expected workspace to plan cleanly under magma"
        end

        def failure_message_when_negated
          "expected workspace not to plan cleanly under magma, but it did:\n#{@report.inspect}"
        end

        def description
          desc = +"plan cleanly under magma"
          desc << " with providers #{@required_providers.inspect}" unless @required_providers.empty?
          desc << " emitting ≥#{@min_resource_changes} resource_changes" if @min_resource_changes
          desc << " declaring resource types #{@resource_types.inspect}" unless @resource_types.empty?
          desc
        end
      end

      class CompatibleWithBackend
        def initialize(backend)
          @backend = backend
          @requires = {}
        end

        # @example .requiring_feature(:in_memory_pipeline)
        def requiring_feature(feature)
          @requires[:feature] = feature
          self
        end

        # @example .requiring_input_format('terraform-json')
        def requiring_input_format(format)
          @requires[:input_format] = format
          self
        end

        def matches?(_workspace_path_or_nil = nil)
          Pangea::Backend.verify_compatible!(@backend, @requires)
          true
        rescue Pangea::Backend::BackendIncompatible => e
          @failure_message = e.message
          false
        rescue Pangea::Backend::BackendUnavailable => e
          @failure_message = "backend #{@backend} unavailable: #{e.message}"
          false
        end

        def failure_message
          @failure_message || "expected backend #{@backend} to be compatible with requires=#{@requires.inspect}"
        end

        def description
          "be compatible with backend #{@backend.inspect}"
        end
      end

      def plan_cleanly_under_magma
        PlanCleanlyUnderMagma.new
      end

      def be_compatible_with_backend(name)
        CompatibleWithBackend.new(name)
      end
    end
  end
end

if defined?(RSpec)
  RSpec.configure do |config|
    config.include Pangea::Magma::Matchers
  end
end
