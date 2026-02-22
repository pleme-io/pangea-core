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

# Core types
require_relative 'pangea/resources/types'
require_relative 'pangea/resource_registry'
require_relative 'pangea/resources/helpers'
require_relative 'pangea/resources/base'
require_relative 'pangea/resources/base_attributes'
require_relative 'pangea/resources/reference'
require_relative 'pangea/resources/network_helpers'
