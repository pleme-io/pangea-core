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
    resource_registry.rb            # Auto-discovery of provider modules
    component_registry.rb           # Thread-safe component registry
    validation.rb                   # Cross-cutting validation
    errors.rb                       # Custom error types
    logging.rb                      # Logging utilities
```

## Type System

### BaseAttributes

All resource attribute classes inherit from `BaseAttributes < Dry::Struct`. Key features:

- `TERRAFORM_REF_PATTERN = /\$\{.*\}/` — detects Terraform interpolation strings
- `terraform_reference?(value)` — class method for reference detection
- `terraform_ref_or(attr_name) { |val| ... }` — skip validation for refs
- `copy_with(changes)` — immutable copy with merged changes

### Typing Strategy

- **Runtime validation:** dry-types/dry-struct with constrained types
- **Type bypass:** Terraform references (`${...}`) skip type validation via `self.new` override
- **Future:** RBS signatures for static analysis (no Sorbet migration)

### ResourceBuilder DSL

```ruby
module MyResource
  include Pangea::Resources::ResourceBuilder

  define_resource :terraform_type,
    attributes_class: Types::MyAttributes,
    outputs: { id: :id, arn: :arn },
    map: [:name],                    # Always set
    map_present: [:description],     # Set when non-nil
    map_bool: [:enable_feature],     # Set when not nil (explicit bool check)
    tags: true,                      # Apply tags block
    labels: false                    # No labels
end
```

### ResourceReference

Returned by every resource function. Provides:
- `ref(attribute_name)` — `${type.name.attribute}`
- `.id`, `.arn`, `.name` — shorthand outputs
- `register_computed_attributes(mapping)` — per-resource computed properties
- `method_missing` delegation to outputs/computed

### SynthesisTestHelpers

```ruby
include Pangea::Testing::SynthesisTestHelpers

let(:synth) { create_synthesizer }
let(:result) { normalize_synthesis(synth.synthesis) }

validate_terraform_structure(result, :resource)
validate_resource_structure(result, 'aws_vpc', 'main')
validate_resource_references(result)
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
