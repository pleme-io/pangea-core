# frozen_string_literal: true

module Pangea
  # Output category management for Terraform templates.
  #
  # Outputs are classified into categories that can be independently toggled:
  #
  #   :display  — Human-readable info (cluster_name, backend type)
  #   :data     — Machine-consumable values for cross-template wiring (vpc_id, role_arn)
  #
  # Configuration is set on the synthesizer context before outputs are declared:
  #
  #   # In template:
  #   self.pangea_output_config = { display: true, data: true }  # default: all on
  #   self.pangea_output_config = { display: false, data: true }  # suppress display
  #   self.pangea_output_config = { display: false, data: false } # suppress all
  #
  #   pangea_output :cluster_name, category: :display do
  #     value cluster_name
  #     description "K3s cluster name"
  #   end
  #
  #   pangea_output :vpc_id, category: :data do
  #     value result.network.vpc.id
  #     description "VPC ID"
  #   end
  #
  # When a category is disabled, the output block is not emitted to Terraform JSON.
  #
  module Outputs
    # Default: all outputs enabled
    DEFAULT_CONFIG = { display: true, data: true }.freeze

    # Set output rendering configuration.
    # Called on the synthesizer context (self in a template).
    def pangea_output_config=(config)
      @_pangea_output_config = DEFAULT_CONFIG.merge(config)
    end

    # Get current output configuration.
    def pangea_output_config
      @_pangea_output_config || DEFAULT_CONFIG.dup
    end

    # Declare a categorized output.
    #
    # @param name [Symbol] Output name (e.g., :vpc_id)
    # @param category [Symbol] :display or :data (default: :data)
    # @param block [Block] Output body (value, description, sensitive)
    #
    # The output is only emitted if its category is enabled in pangea_output_config.
    # If no category is specified, defaults to :data (always emitted unless data is off).
    def pangea_output(name, category: :data, &block)
      config = pangea_output_config

      # Master kill switch: if ALL categories are off, emit nothing
      return if config.values.none?

      # Category-specific toggle
      return unless config.fetch(category, true)

      # Delegate to the synthesizer's native output method
      output(name, &block)
    end

    # Convenience: declare a display-only output.
    def display_output(name, &block)
      pangea_output(name, category: :display, &block)
    end

    # Convenience: declare a data output (for cross-template wiring).
    def data_output(name, &block)
      pangea_output(name, category: :data, &block)
    end

    # Suppress all outputs (useful for module mode where outputs are internal).
    def suppress_all_outputs!
      self.pangea_output_config = { display: false, data: false }
    end

    # Suppress only display outputs (keep data for wiring).
    def suppress_display_outputs!
      self.pangea_output_config = { display: false, data: true }
    end

    # Enable all outputs (default state).
    def enable_all_outputs!
      self.pangea_output_config = { display: true, data: true }
    end
  end
end
