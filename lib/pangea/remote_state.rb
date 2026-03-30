# frozen_string_literal: true

require 'json'

module Pangea
  # Cross-template state references — reads outputs directly from S3 state.
  #
  # No Terraform data sources needed. At synthesis time, reads the other
  # template's .tfstate from S3, extracts the output value, and returns
  # it as a literal string. This makes cross-template wiring simple and
  # dependency-free.
  #
  # Usage in a template:
  #   vpc_id = Pangea::RemoteState.from_template(ws,
  #     template: 'akeyless-dev-cluster',
  #     output: :vpc_id,
  #   )
  #   # => "vpc-06b5744a5287e2d47" (actual VPC ID from state)
  #
  # Or with explicit config:
  #   vpc_id = Pangea::RemoteState.output(
  #     template: 'akeyless-dev-cluster',
  #     output: :vpc_id,
  #     bucket: 'pangea-terraform-state-376129857990',
  #     region: 'us-east-1',
  #   )
  #
  module RemoteState
    # Track implicit dependencies between templates.
    @dependencies = {}

    class << self
      attr_reader :dependencies

      # Read an output directly from another template's S3 state file.
      #
      # @param template [String] Source template name (state key prefix)
      # @param output [Symbol, String] Output name to read
      # @param bucket [String] S3 bucket name
      # @param region [String] AWS region
      # @param state_key [String] Override state key (default: "{template}/terraform.tfstate")
      # @return [String, nil] The output value, or nil if not found
      def output(template:, output:, bucket:, region: 'us-east-1', state_key: nil)
        key = state_key || "#{template}/terraform.tfstate"
        state = fetch_state(bucket: bucket, key: key, region: region)
        return nil unless state

        extract_output(state, output.to_s)
      end

      # Read an output using WorkspaceConfig for backend details.
      #
      # @param ws [Pangea::WorkspaceConfig] Workspace configuration
      # @param template [String] Source template name
      # @param output [Symbol, String] Output name to read
      # @return [String, nil] The output value, or nil if not found
      def from_template(ws, template:, output:)
        sc = ws.respond_to?(:state_config) ? ws.state_config : {}
        bucket = sc['bucket'] || sc[:bucket]
        region = sc['region'] || sc[:region] || 'us-east-1'

        raise ArgumentError, "WorkspaceConfig has no state bucket configured" unless bucket

        # Track dependency
        @dependencies[template] ||= []

        self.output(template: template, output: output, bucket: bucket, region: region)
      end

      # Get all templates this workspace depends on.
      #
      # @return [Hash] Map of template_name => [output_names_read]
      def dependency_graph
        @dependencies.dup
      end

      # Reset (for testing).
      def reset!
        @dependencies = {}
      end

      private

      # Fetch and parse a Terraform state file from S3.
      def fetch_state(bucket:, key:, region:)
        # Use AWS CLI to read state (available in all pangea dev shells)
        cmd = "aws s3 cp s3://#{bucket}/#{key} - --region #{region} 2>/dev/null"
        json = `#{cmd}`
        return nil if json.nil? || json.empty? || $?.exitstatus != 0

        JSON.parse(json)
      rescue JSON::ParserError
        nil
      end

      # Extract an output value from parsed Terraform state.
      def extract_output(state, output_name)
        # Terraform state format: { "outputs": { "name": { "value": "..." } } }
        outputs = state.dig('outputs') || {}
        output_entry = outputs[output_name]
        return nil unless output_entry

        output_entry['value']
      end
    end
  end
end
