# frozen_string_literal: true

module Pangea
  module Tagging
    # A canonical tag set with provider-specific format transformations.
    #
    # Wraps a Hash of symbol-keyed tags and provides methods to convert
    # to every provider's expected tag/label format. Tags are defined once
    # and transformed at the point of use.
    #
    # Usage:
    #   tags = TagSet.new(ManagedBy: 'pangea', Team: 'platform', Name: 'my-vpc')
    #   tags.merge(Environment: 'dev')
    #
    #   # AWS resources (simple map)
    #   ctx.aws_vpc(:vpc, tags: tags.to_aws)
    #
    #   # AWS ASG (block-based tags with propagation)
    #   ctx.aws_autoscaling_group(:asg, tag: tags.to_aws_asg)
    #
    #   # AWS Launch Template (nested tag_specifications)
    #   ctx.aws_launch_template(:lt, tag_specifications: tags.to_aws_tag_spec)
    #
    #   # GCP / Hcloud (lowercase label keys)
    #   ctx.google_compute_instance(:vm, labels: tags.to_gcp)
    #   ctx.hcloud_server(:srv, labels: tags.to_hcloud)
    #
    #   # Azure (same as AWS)
    #   ctx.azurerm_resource_group(:rg, tags: tags.to_azure)
    #
    class TagSet
      attr_reader :entries

      def initialize(tags = {})
        @entries = tags.each_with_object({}) do |(k, v), h|
          h[k.to_sym] = v.to_s
        end.freeze
      end

      # Create a new TagSet with additional tags merged in.
      # Does not mutate the original.
      def merge(extra = {})
        self.class.new(@entries.merge(extra))
      end

      # ── AWS Formats ──────────────────────────────────────────────

      # Simple AWS tags map: { "Key" => "value" }
      # Used by: aws_vpc, aws_subnet, aws_security_group, aws_lb, aws_iam_role, aws_s3_bucket, etc.
      def to_aws
        @entries.transform_keys(&:to_s)
      end

      # AWS ASG tags: [{ key: "K", value: "V", propagate_at_launch: true }, ...]
      # Used by: aws_autoscaling_group `tag` attribute
      def to_aws_asg(propagate: true)
        @entries.map { |k, v| { key: k.to_s, value: v.to_s, propagate_at_launch: propagate } }
      end

      # AWS Launch Template tag_specifications:
      # [{ resource_type: "instance", tags: { "Key" => "value" } }]
      # Used by: aws_launch_template inside `tag_specifications` attribute
      def to_aws_tag_spec(resource_type: 'instance')
        [{ resource_type: resource_type, tags: to_aws }]
      end

      # ── GCP Format ─────────────────────────────────────────────

      # GCP labels: lowercase keys, only [a-z0-9_-], max 63 chars.
      # Values also lowercased and sanitized.
      # Used by: google_compute_*, google_container_cluster, etc.
      def to_gcp
        @entries.each_with_object({}) do |(k, v), h|
          key = sanitize_label(k.to_s)
          val = sanitize_label(v.to_s)
          h[key] = val
        end
      end

      # ── Azure Format ───────────────────────────────────────────

      # Azure tags: same format as AWS (string key-value map)
      # Used by: azurerm_resource_group, azurerm_kubernetes_cluster, etc.
      def to_azure
        to_aws
      end

      # ── Hcloud Format ──────────────────────────────────────────

      # Hcloud labels: same format as GCP (lowercase, sanitized)
      # Used by: hcloud_server, hcloud_network, etc.
      def to_hcloud
        to_gcp
      end

      # ── Kubernetes Format ─────────────────────────────────────
      # Kubernetes labels: lowercase keys with optional prefix (e.g., "app.kubernetes.io/name")
      # Same sanitization as GCP but allows "/" and "." in keys
      def to_kubernetes
        @entries.each_with_object({}) do |(k, v), h|
          key = k.to_s.downcase.gsub(/[^a-z0-9_.\/\-]/, '-')
          val = v.to_s
          h[key] = val
        end
      end

      # Kubernetes annotations: arbitrary key-value (no sanitization needed)
      def to_kubernetes_annotations
        @entries.transform_keys(&:to_s)
      end

      # ── Cloudflare Format ──────────────────────────────────────

      # Cloudflare tags: array of "key:value" strings
      # Used by: cloudflare_record (tags attribute is an array of strings)
      def to_cloudflare
        @entries.map { |k, v| "#{k}:#{v}" }
      end

      # ── Datadog Format ─────────────────────────────────────────

      # Datadog tags: array of "key:value" strings
      # Used by: datadog_monitor, datadog_dashboard, etc.
      def to_datadog
        @entries.map { |k, v| "#{k}:#{v}" }
      end

      # ── Vault Format ──────────────────────────────────────────
      # Vault tags: array of "key:value" strings
      def to_vault
        @entries.map { |k, v| "#{k}:#{v}" }
      end

      # ── MongoDBAtlas Format ────────────────────────────────────
      # MongoDB Atlas tags: array of {key: "K", value: "V"} objects
      def to_mongodbatlas
        @entries.map { |k, v| { key: k.to_s, value: v.to_s } }
      end

      # ── GitHub Format ─────────────────────────────────────────
      # GitHub labels: simple string array (just the keys, no values)
      def to_github_labels
        @entries.keys.map(&:to_s)
      end

      # ── Consul Format ─────────────────────────────────────────
      # Consul: simple map like AWS
      def to_consul
        to_aws
      end

      # ── Nomad Format ──────────────────────────────────────────
      # Nomad: uses "meta" block with lowercase keys
      def to_nomad
        to_gcp
      end

      # ── Auto-format Detection ─────────────────────────────────

      # Transform for a specific resource type (auto-detect format).
      # Returns { attribute_name => transformed_value }
      def for_resource(resource_type)
        TagAdapter.transform(self, resource_type)
      end

      # ── Raw Access ─────────────────────────────────────────────

      # Hash-style access for backward compatibility
      def [](key)
        @entries[key.to_sym]
      end

      def key?(key)
        @entries.key?(key.to_sym)
      end

      def to_h
        @entries.dup
      end

      def to_s
        "TagSet(#{@entries.length} tags)"
      end

      def inspect
        "TagSet(#{@entries.inspect})"
      end

      # Iterate over entries
      def each(&block)
        @entries.each(&block)
      end

      private

      def sanitize_label(str)
        str.downcase.gsub(/[^a-z0-9_-]/, '_')[0, 63]
      end
    end
  end
end
