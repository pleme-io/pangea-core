# pangea-core

Foundation library for the Pangea infrastructure DSL. Provides the type system,
resource builder DSL, synthesis test helpers, and cross-provider composition primitives.

All provider gems (pangea-aws, pangea-akeyless, pangea-cloudflare, etc.) depend on this.

## Structure

```
lib/
  pangea-core.rb                    # Entry point
  pangea-core/version.rb            # VERSION constant
  pangea/
    resources/
      base.rb                       # Base resource definitions
      base_attributes.rb            # BaseAttributes < Dry::Struct (TERRAFORM_REF_PATTERN)
      resource_builder.rb           # define_resource / define_data DSL
      reference.rb                  # ResourceReference with computed attributes
      types.rb                      # Core type definitions (AwsTags, etc.)
      helpers.rb                    # Shared resource helpers
      builders/output_builder.rb    # Output extraction helpers
      validators/                   # Network/format validators
    types/
      registry.rb                   # Type registry (CidrBlock, Port, Protocol, etc.)
      base_types.rb                 # Constrained types for IaC
      domain_types.rb               # Higher-level domain types
    entities/
      namespace.rb                  # Terraform state backend config
      module_definition.rb          # Reusable module metadata
    components/
      base.rb                       # Validation, networking, naming helpers
    testing/
      synthesis_test_helpers.rb     # RSpec helpers: create_synthesizer, normalize_synthesis, validate_*
      mock_terraform_synthesizer.rb # Fallback mock for testing
      spec_setup.rb                 # SpecSetup.configure!
    contracts.rb                    # Typed interface contracts (require aggregator)
    contracts/
      architecture_result.rb        # ArchitectureResult contract
      cluster_result.rb             # ClusterResult contract
      iam_result.rb                 # IamResult contract
      network_result.rb             # NetworkResult contract
      security_group_accessor.rb    # SecurityGroupAccessor contract
      errors.rb                     # Contract violation errors
    resource_registry.rb            # Auto-discovery of provider modules
    component_registry.rb           # Thread-safe component registry
    validation.rb                   # Cross-cutting validation
    errors.rb                       # Custom error types
    logging.rb                      # Logging utilities
```

## Dependencies

- dry-struct ~> 1.6, dry-types ~> 1.7
- terraform-synthesizer ~> 0.0.28
- Ruby >= 3.3.0, MIT license

## Testing

```sh
bundle exec rspec               # All tests
nix run .#test                   # Via nix
```

---

## Unified Pangea Ecosystem Pattern

This section is the single source of truth for how templates, resources,
architectures, and tests are structured across all pangea-* repos.

### Abstraction Layer Hierarchy

Never skip layers. Each layer composes the one below it.

```
4. Flows      (pangea.yml / fleet.yaml)  — multi-template orchestration
3. Templates  (template :name do...end)  — state boundaries (one template = one .tfstate)
2. Architectures (Module.build(synth, config)) — reusable compositions
1. Typed Resource Functions (synth.aws_vpc) — atomic, one function = one Terraform resource
```

---

### Resource Pattern

Every typed resource function follows this contract:

1. **Type validation** via `Types::*Attributes` (Dry::Struct subclass of `BaseAttributes`)
   - `TERRAFORM_REF_PATTERN = /\$\{.*\}/` detects interpolation strings
   - `terraform_ref_or(attr_name) { |val| ... }` skips validation for refs
   - `copy_with(changes)` for immutable copies

2. **Resource method** in `Pangea::Resources::{Provider}` module, built with `ResourceBuilder`:
   ```ruby
   module MyResource
     include Pangea::Resources::ResourceBuilder

     define_resource :terraform_type,
       attributes_class: Types::MyAttributes,
       outputs: { id: :id, arn: :arn },
       map: [:name],            # Always set
       map_present: [:desc],    # Set when non-nil
       map_bool: [:enabled],    # Explicit bool check
       tags: true
   end
   ```

3. **Returns `ResourceReference`** with outputs and computed properties:
   - `ref(attribute_name)` produces `${type.name.attribute}`
   - `.id`, `.arn`, `.name` shorthand outputs
   - `register_computed_attributes(mapping)` for per-resource computed props
   - `method_missing` delegation to outputs/computed

4. **Template access** via extend guard:
   ```ruby
   self.extend(Pangea::Resources::AWS) unless respond_to?(:aws_vpc)
   ```

### ResourceInput — Serialization Boundary

ResourceInput partitions user-provided attributes into validated literals
and opaque Terraform references. Types stay PURE — they model the domain.
Refs handled at the serialization boundary, not in type definitions.

```ruby
input = ResourceInput.partition(VpcAttributes, {
  cidr: "10.0.0.0/16",              # Literal — validated by Dry::Struct
  vpc_id: "${aws_vpc.other.id}",     # Ref — frozen, passed through
})
input[:cidr]   # => "10.0.0.0/16"   (validated)
input[:vpc_id] # => "${aws_vpc.other.id}" (opaque)
```

Key invariants (proven by 24 RSpec tests):
- Literal values validated strictly per-field against Dry::Types constraints
- Only `\A\$\{.+\}\z` strings bypass validation (not partial matches)
- Required attributes must be in EITHER literals or refs (not missing from both)
- ResourceInput is frozen after creation (immutable)
- `[]` accessor resolves refs over literals
- `.load` used for Dry::Struct construction (bypasses missing-key for ref fields)

Equivalent to Rust's serde boundary: type is strict, serialization handles wire format.

### Pangea::Secrets — Unified Secret Resolution

Three-tier resolution chain (first match wins):
1. Environment variable (CI override)
2. sops-nix pre-decrypted file (~/.config/sops-nix/secrets/)
3. SOPS CLI extraction (fallback)

```ruby
Pangea::Secrets.configure(sops_file: '/path/to/secrets.yaml')
api_key = Pangea::Secrets.resolve('porkbun/api-key')
# Tries: ENV['PORKBUN_API_KEY'] → sops-nix file → sops --decrypt
```

### Type Purity Discipline

Generated types (from pangea-forge) are PURE:
```ruby
attribute :cidr_block, T::CidrBlock     # Strict — validated at synthesis
attribute :nameservers, T::Array.of(T::String)  # No ref unions
```

Terraform references are handled by ResourceBuilder → ResourceInput,
NOT by the type system. Types model the domain. The serialization
boundary handles the wire format.

**Hard rules:**
- Never add `| T::Ref` to generated types
- Never override BaseAttributes.new to intercept refs
- ResourceInput.partition is the ONLY place refs are separated from literals

### Library Types (T::Ref, T::RefOr)

Available in `types/core.rb` for HAND-WRITTEN code that explicitly needs
to model the ref domain. Auto-generated code does NOT use these.

```ruby
T::Ref                          # Constrained: /\A\$\{.+\}\z/
T::RefOr(T::CidrBlock)         # CidrBlock | Ref (explicit sum type)
```

---

### Template Pattern

Every template (state boundary) follows this structure:

```ruby
require 'pangea-aws'          # 1. Require provider gems
require 'digest'
require 'pangea/workspace_config'

template :my_template do
  # 2. Cryptographic fingerprint
  template_fingerprint = Digest::SHA256.hexdigest(File.read(__FILE__))

  # 3. Load workspace config (root pangea.yml <- workspace pangea.yml)
  ws = Pangea::WorkspaceConfig.load(__dir__)

  # 4. Configuration (ENV overrides with sensible defaults)
  region = ENV.fetch('REGION', 'us-east-1')
  config = {
    tags: ws.tags.merge(
      PangeaFingerprint: template_fingerprint,
      InfraLayer: 'my-template',
    ),
  }

  # 5. Declare provider BEFORE architecture call
  provider :aws, region: region

  # 6. Call architecture (NEVER raw resource blocks)
  result = Pangea::Architectures::MyArch.build(self, config)

  # 7. Declare outputs
  output :vpc_id do
    value result[:vpc].id
    description "VPC ID"
  end
end
```

**Hard rules:**
- Templates MUST NOT contain `resource :type, :name do...end` blocks
- Templates call architectures or typed resource functions only
- Provider declared before any architecture call
- No inline `ManagedBy` tags -- inherit from root `pangea.yml` via `ws.tags`
- Fingerprint computed from `File.read(__FILE__)` for tamper detection

---

### Architecture Pattern

Each architecture is a Ruby module with `.build(synth, config)`:

```ruby
module Pangea
  module Architectures
    module MyArchitecture
      PROFILES = {
        dev: { encryption: 'AES256' }.freeze,
        production: { encryption: 'aws:kms', versioning: true }.freeze,
      }.freeze

      def self.build(synth, config = {})
        # Validate required params
        raise ArgumentError, ':name is required' unless config[:name]

        # Extend provider module (idempotent guard)
        synth.extend(Pangea::Resources::AWS) unless synth.respond_to?(:aws_vpc)

        # Apply profile defaults, user config wins
        profile = PROFILES.fetch(config.fetch(:profile, :dev))
        effective = profile.merge(config)

        # 4-phase pipeline (for cluster architectures):
        #   1. Network  -- VPC, subnets, IGW, NAT, S3 buckets
        #   2. IAM      -- roles, policies, instance profiles
        #   3. Cluster  -- control plane ASG, NLB, cloud-init
        #   4. Node Pools -- worker ASGs, launch templates

        vpc = synth.aws_vpc(:"#{effective[:name]}-vpc", { ... })

        # Return references hash
        { vpc: vpc }
      end
    end
  end
end
```

**Hard rules:**
- Architectures call typed resource functions or other architectures only
- All parameters have defaults where sensible (`Dry::Struct .default()`)
- Security invariants enforced at this layer (least-privilege, no wildcards)
- Profiles are `FROZEN` constants; user config always overrides profile defaults
- Can compose other architectures (e.g., `K3sDevCluster` composes `K3sClusterIam`)

---

### Test Pattern

Four test categories, each with distinct concerns:

#### 1. Workspace specs -- string assertions on template content, YAML config

```ruby
RSpec.describe 'my-workspace' do
  let(:template_content) { File.read('my_template.rb') }
  let(:workspace_config) { YAML.safe_load(File.read('pangea.yml')) }

  it 'calls architecture, not raw resources' do
    expect(template_content).to include('MyArch.build')
  end

  it 'has no inline ManagedBy tag' do
    expect(template_content).not_to include("ManagedBy: 'pangea'")
  end

  it 'declares provider before architecture call' do
    lines = template_content.lines
    provider_idx = lines.index { |l| l.strip.start_with?('provider :aws') }
    arch_idx = lines.index { |l| l.include?('MyArch.build') }
    expect(provider_idx).to be < arch_idx
  end
end
```

#### 2. Synthesis specs -- full Terraform JSON validation

```ruby
RSpec.describe Pangea::Architectures::MyArch do
  include Pangea::Testing::SynthesisTestHelpers

  let(:synth) { create_synthesizer }
  let(:result) do
    described_class.build(synth, config)
    normalize_synthesis(synth.synthesis)
  end

  it 'produces valid Terraform JSON' do
    validate_terraform_structure(result, :resource)
  end

  it 'creates expected resource' do
    config = validate_resource_structure(result, 'aws_vpc', 'main')
    expect(config['cidr_block']).to eq('10.0.0.0/16')
  end

  it 'produces deterministic output' do
    s1 = create_synthesizer; described_class.build(s1, config)
    s2 = create_synthesizer; described_class.build(s2, config)
    expect(s1.synthesis.to_json).to eq(s2.synthesis.to_json)
  end
end
```

#### 3. Type specs -- validation of config types with edge cases

Test constrained types, Terraform reference bypass, `copy_with`, and
required/optional field behavior.

#### 4. Security specs -- invariant assertions on synthesized output

```ruby
RSpec.describe 'MyArch security invariants' do
  include Pangea::Testing::SynthesisTestHelpers

  it 'does not allow SSH from 0.0.0.0/0' do
    sg = validate_resource_structure(result, 'aws_security_group', 'nodes')
    ssh_rules = Array(sg['ingress']).select { |r| r['from_port'] == 22 }
    ssh_rules.each do |rule|
      expect(Array(rule['cidr_blocks'])).not_to include('0.0.0.0/0')
    end
  end

  it 'all launch templates require IMDSv2' do
    lts = result.dig('resource', 'aws_launch_template') || {}
    lts.each do |name, lt|
      metadata = lt['launch_template_data']['metadata_options']
      expect(metadata['http_tokens']).to eq('required')
    end
  end
end
```

---

### Security Invariants

These are enforced at the architecture and test layers:

1. **`account_id` required** for IAM policy scoping -- backend raises if `CHANGEME`
2. **`etcd_backup_bucket` required** for S3 policy scoping
3. **SSH/API CIDRs must not be `0.0.0.0/0`** -- default to `10.0.0.0/8`
4. **Provider declared before architecture call** -- tested by workspace specs
5. **No inline ManagedBy tags** -- inherit from root `pangea.yml` via `ws.tags`
6. **VPN configs validated** through `Types::VpnConfig`
7. **IMDSv2 required** on all launch templates (`http_tokens: required`, hop limit 1)
8. **All S3 buckets** block public access (4 boolean flags all true)
9. **All EBS volumes** encrypted
10. **IAM roles** have `prevent_destroy` lifecycle and 1-hour max session
11. **All compute via ASG** -- no raw `aws_instance` resources
12. **Private subnets route through NAT**, not IGW directly

---

### FluxCD Integration

Templates that bootstrap FluxCD follow this config shape:

```ruby
cluster_config[:fluxcd] = {
  source_url:     'ssh://git@github.com/org/k8s-repo',  # SSH auth (org disables deploy keys)
  source_branch:  'main',
  source_auth:    'ssh',
  reconcile_path: "./clusters/#{cluster_name}",          # Per-cluster kustomization path
  sops_enabled:   true,                                  # SOPS for encrypted secrets
}
```

- **Source URL:** SSH with key auth (org policy disables deploy keys, use user keys)
- **Secret ref:** `flux-system` namespace secret (created by bootstrap)
- **SOPS:** Enabled for encrypted secrets in Git
- **Reconcile path:** `./clusters/{cluster_name}` convention

---

### Workspace Config

`Pangea::WorkspaceConfig.load(__dir__)` merges two layers of `pangea.yml`:

```
repo-root/pangea.yml       # Global: tags (ManagedBy, Team), S3 defaults, shared namespaces
  workspace/pangea.yml     # Local: workspace tags (Purpose, Cluster), namespace overrides
```

- Tags merge with workspace winning on conflict
- S3 defaults (bucket, region, dynamodb_table) inject into S3-typed namespaces
- Local namespaces can override S3 defaults
- `bootstrap` namespace always uses local state (no circular dependency)
- Results are frozen and cached
- Dependency injection via `ConfigSource`, `ConfigDiscovery`, `TagMerger`, `NamespaceMerger`

---

### SynthesisTestHelpers API

```ruby
include Pangea::Testing::SynthesisTestHelpers

synth = create_synthesizer
result = normalize_synthesis(synth.synthesis)

validate_terraform_structure(result, :resource)
validate_resource_structure(result, 'aws_vpc', 'main')  # Returns resource config hash
validate_resource_references(result)
```

---

### Type System

- **Runtime validation:** dry-types/dry-struct with constrained types
- **Type bypass:** Terraform references (`${...}`) skip type validation via `BaseAttributes.new` override
- **`BaseAttributes`** provides `terraform_reference?`, `terraform_ref_or`, `copy_with`
- **`ResourceBuilder` DSL:** `define_resource` / `define_data` with `map`, `map_present`, `map_bool`, `tags`, `labels`
- **Coercion types:** `PortString` (Integer->String), `PortInt` (String->Integer, 0-65535), `CoercibleBool` (String/Integer->Bool)
- **Future:** RBS signatures for static analysis (no Sorbet migration)

---

### Contracts Module (Pangea::Contracts)

Typed interfaces that backends must return and templates can rely on. Each
contract is a Dry::Struct defining required/optional fields with type validation.

| Contract | Purpose | Key fields |
|----------|---------|------------|
| `NetworkResult` | VPC/network phase output | vpc, subnets, security_groups, nat |
| `IamResult` | IAM phase output | roles, policies, instance_profiles |
| `ClusterResult` | Cluster phase output | control_plane, endpoint, certificate_authority |
| `ArchitectureResult` | Full architecture return | network, iam, cluster, node_pools |

Backends return these contracts from their phase methods. Templates and
architectures can rely on the typed fields without provider-specific knowledge.
`SecurityGroupAccessor` provides a unified interface for accessing SG IDs
across providers.

### Coercion Types

Located in `lib/pangea/resources/types/coercions.rb`. Handle common type
mismatches from YAML configs, CLI args, and API responses.

| Type | Accepts | Produces | Use case |
|------|---------|----------|----------|
| `PortString` | Integer, String | String | AWS health_check.port, listener.port |
| `PortInt` | String, Integer | Integer (0-65535) | Port number validation |
| `CoercibleBool` | String, Integer, Bool | Bool | YAML/CLI boolean coercion |

### ResourceReference method_missing

`ResourceReference` uses `method_missing` as a catch-all to delegate to
outputs and computed attributes. Calling `ref.id` is equivalent to
`ref.outputs[:id]` or `ref.ref(:id)`. Unknown attributes raise
`NoMethodError` with a helpful message listing available outputs.

---

### ResourceBuilder Strict Validation

`ResourceBuilder` enforces strict unknown-key detection on attribute hashes.
Any key not declared in the `Dry::Struct` attributes class raises an error at
synthesis time, preventing silent typo-based misconfigurations.

Terraform meta-arguments (`lifecycle`, `depends_on`, `count`, `for_each`,
`provider`, `provisioner`) are separated before attribute validation. They
are passed through to the resource block without type checking, so they never
trigger unknown-key errors.

---

### TagSet and TagAdapter

Canonical tagging system that handles provider-specific tag format differences.

**TagSet** — immutable set of key-value tags with provider-specific transforms:
- `TagSet.new(tags_hash)` creates a canonical tag set
- `#for_provider(:aws)`, `#for_provider(:gcp)`, etc. produce provider-native format
- Infrastructure params (e.g., `propagate_at_launch`) are NOT tags — use typed config fields

**TagAdapter** — auto-detects the correct tag format per resource type:

| Format family | Example resources | Shape |
|---------------|-------------------|-------|
| AWS map | `aws_vpc`, `aws_subnet` | `tags: { Key: "Value" }` |
| ASG propagation | `aws_autoscaling_group` | `tag { key, value, propagate_at_launch }` blocks |
| Tag specifications | `aws_launch_template` | `tag_specifications [{ resource_type, tags }]` |
| GCP labels | `google_*` | `labels: { key: "value" }` |
| Key-value arrays | `azurerm_*` | `tags: [{ key: "k", value: "v" }]` |
| MongoDB objects | `mongodbatlas_*` | `tags: [{ key: "k", value: "v" }]` |

---

### Categorized Outputs

Outputs are split into two categories for cleaner template ergonomics:

| Helper | Category | Purpose |
|--------|----------|---------|
| `pangea_output` | data | Always emitted — used by downstream templates via `terraform_remote_state` |
| `display_output` | display | Shown in terminal after apply — human-readable summaries |
| `data_output` | data | Alias for `pangea_output` (explicit intent) |

**Suppression:**
- `suppress_display_outputs!` — hides display outputs (CI/CD mode)
- `suppress_all_outputs!` — hides everything (library templates)

Templates use `display_output` for human-facing values (URLs, IPs) and
`data_output` / `pangea_output` for machine-consumed values (IDs, ARNs).
