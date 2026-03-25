# frozen_string_literal: true

module Pangea
  module Tagging
    # Registry mapping Terraform resource type prefixes to tag transform methods.
    #
    # When a resource is synthesized, the adapter automatically selects the
    # correct format based on the resource type. Patterns are checked in order
    # -- first match wins -- so specific patterns (e.g. aws_autoscaling_group)
    # must appear before general ones (e.g. aws_*).
    #
    # Usage:
    #   TagAdapter.format_for(:aws_vpc)
    #   # => { pattern: /^aws_/, method: :to_aws, attr: :tags }
    #
    #   TagAdapter.transform(tag_set, :google_compute_instance)
    #   # => { labels: { "managedby" => "pangea", ... } }
    #
    class TagAdapter
      # Registry mapping resource type patterns to tag format methods.
      # Checked in order -- first match wins.
      FORMATS = [
        # AWS ASG uses block-based tags (singular `tag`)
        { pattern: /^aws_autoscaling_group$/, method: :to_aws_asg, attr: :tag },

        # AWS Launch Template uses nested tag_specifications
        { pattern: /^aws_launch_template$/, method: :to_aws_tag_spec, attr: :tag_specifications },

        # AWS (default) -- simple map tags
        { pattern: /^aws_/, method: :to_aws, attr: :tags },

        # Azure -- same as AWS
        { pattern: /^azurerm_/, method: :to_azure, attr: :tags },

        # GCP -- lowercase labels
        { pattern: /^google_/, method: :to_gcp, attr: :labels },

        # Hcloud -- lowercase labels
        { pattern: /^hcloud_/, method: :to_hcloud, attr: :labels },

        # Kubernetes -- labels (not annotations)
        { pattern: /^kubernetes_/, method: :to_kubernetes, attr: :labels },

        # Datadog -- array of "key:value" strings
        { pattern: /^datadog_/, method: :to_datadog, attr: :tags },

        # Cloudflare -- array of "key:value" strings
        { pattern: /^cloudflare_/, method: :to_cloudflare, attr: :tags },

        # Vault -- array strings
        { pattern: /^vault_/, method: :to_vault, attr: :tags },

        # MongoDBAtlas -- array of {key, value}
        { pattern: /^mongodbatlas_/, method: :to_mongodbatlas, attr: :tags },

        # Consul -- simple map
        { pattern: /^consul_/, method: :to_consul, attr: :tags },

        # Nomad -- lowercase labels
        { pattern: /^nomad_/, method: :to_nomad, attr: :meta },

        # Default fallback -- simple map
        { pattern: /.*/, method: :to_aws, attr: :tags },
      ].freeze

      # Look up the correct tag format for a resource type.
      # Returns { pattern:, method:, attr: } or nil.
      def self.format_for(resource_type)
        resource_type_str = resource_type.to_s
        FORMATS.find { |f| f[:pattern].match?(resource_type_str) }
      end

      # Transform a TagSet for a specific resource type.
      # Returns { attribute_name => transformed_value }
      def self.transform(tag_set, resource_type)
        fmt = format_for(resource_type)
        return {} unless fmt && tag_set

        value = tag_set.send(fmt[:method])
        { fmt[:attr] => value }
      end
    end
  end
end
