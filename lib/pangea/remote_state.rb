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
      # @param bucket [String] S3 bucket name (optional if root_config set)
      # @param region [String] AWS region (optional if root_config set)
      # @param state_key [String] Override state key (default: pangea convention)
      # @return [String, nil] The output value, or nil if not found
      def output(template:, output:, bucket: nil, region: nil, state_key: nil)
        bucket ||= @root_bucket
        region ||= @root_region || 'us-east-1'

        raise ArgumentError, "No bucket configured. Call RemoteState.configure or pass bucket:" unless bucket

        # Pangea convention: pangea/{workspace}/{template}/terraform.tfstate
        key = state_key || "pangea/#{template}/#{template.tr('-', '_')}/terraform.tfstate"
        state = fetch_state(bucket: bucket, key: key, region: region)
        return nil unless state

        # Track dependency
        @dependencies[template] ||= []

        extract_output(state, output.to_s)
      end

      # Simple one-liner: read an output from another template.
      # Requires configure() to have been called first (or pass bucket/region).
      #
      # Usage:
      #   Pangea::RemoteState.from('akeyless-dev-cluster', :vpc_id)
      #
      # @param template [String] Source template name
      # @param output [Symbol, String] Output name to read
      # @return [String, nil] The output value
      def from(template, output)
        self.output(template: template, output: output)
      end

      # Configure root state backend defaults (called once at boot).
      # Templates inherit these — no need to pass bucket/region everywhere.
      #
      # @param bucket [String] S3 bucket name
      # @param region [String] AWS region
      def configure(bucket:, region: 'us-east-1')
        @root_bucket = bucket
        @root_region = region
      end

      # Read an output using WorkspaceConfig for backend details.
      # Extracts bucket/region from the root pangea.yml state.s3 config.
      #
      # @param ws [Object] Workspace config (any object with state/s3/bucket)
      # @param template [String] Source template name
      # @param output [Symbol, String] Output name to read
      # @return [String, nil] The output value, or nil if not found
      def from_template(ws, template:, output:)
        # Try to extract bucket from workspace config hierarchy
        bucket = extract_bucket(ws)
        region = extract_region(ws)

        raise ArgumentError, "Cannot determine state bucket from workspace config" unless bucket

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
        @root_bucket = nil
        @root_region = nil
      end

      private

      # Extract S3 bucket from workspace config (tries multiple paths).
      def extract_bucket(ws)
        return @root_bucket if @root_bucket

        # Try: ws.state_config[:bucket], ws.config[:state][:s3][:bucket], etc.
        if ws.respond_to?(:state_config)
          sc = ws.state_config rescue nil
          return sc['bucket'] || sc[:bucket] if sc.is_a?(Hash)
        end

        # Try root YAML config path: state.s3.bucket
        if ws.respond_to?(:raw_config)
          rc = ws.raw_config rescue nil
          return rc.dig('state', 's3', 'bucket') if rc.is_a?(Hash)
        end

        nil
      end

      # Extract region from workspace config.
      def extract_region(ws)
        return @root_region if @root_region

        if ws.respond_to?(:state_config)
          sc = ws.state_config rescue nil
          return sc['region'] || sc[:region] if sc.is_a?(Hash)
        end

        if ws.respond_to?(:raw_config)
          rc = ws.raw_config rescue nil
          return rc.dig('state', 's3', 'region') if rc.is_a?(Hash)
        end

        'us-east-1'
      end

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
