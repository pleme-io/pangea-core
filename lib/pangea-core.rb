# frozen_string_literal: true

require 'dry-struct'
require 'dry-types'
require 'terraform-synthesizer'

# dry-types 1.9+ ConstraintError requires 2 args (message, input).
# Our resource type code uses `raise ConstraintError, "msg"` which passes
# only 1 arg via Ruby's `exception(msg)` method. Patch to accept single arg.
if Dry::Types::ConstraintError.instance_method(:initialize).arity.abs > 1
  class Dry::Types::ConstraintError
    alias_method :_orig_initialize, :initialize
    def initialize(message, input = nil)
      _orig_initialize(message, input)
    end
  end
end

# Minimal ActiveSupport-like extensions used by resource code
unless Object.method_defined?(:present?)
  class Object
    def present?
      respond_to?(:empty?) ? !empty? : !nil?
    end

    def blank?
      respond_to?(:empty?) ? empty? : nil?
    end
  end

  class NilClass
    def present? = false
    def blank? = true
  end

  class FalseClass
    def present? = false
    def blank? = true
  end

  class TrueClass
    def present? = true
    def blank? = false
  end

  class String
    def present? = !empty?
    def blank? = empty? || strip.empty?
  end
end

# Domain types
require_relative 'pangea/types/registry'
require_relative 'pangea/types/base_types'
require_relative 'pangea/types/domain_types'

# Errors and validation
require_relative 'pangea/errors'
require_relative 'pangea/validation'
require_relative 'pangea/resources/validators/network_validators'
require_relative 'pangea/resources/validators/format_validators'

# Entities
require_relative 'pangea/entities'

# Logging
require_relative 'pangea/logging'

# Component infrastructure
require_relative 'pangea/components/base'
require_relative 'pangea/component_registry'

# Resource builders
require_relative 'pangea/resources/builders/output_builder'

# Core resource types
require_relative 'pangea/resources/types'
require_relative 'pangea/resource_registry'
require_relative 'pangea/resources/helpers'
require_relative 'pangea/resources/base'
require_relative 'pangea/resources/base_attributes'
require_relative 'pangea/resources/reference'
require_relative 'pangea/resources/resource_builder'
require_relative 'pangea/resources/network_helpers'
