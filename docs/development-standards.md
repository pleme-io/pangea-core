# Pangea Development Standards

Standards for all pangea-* repositories. Every contributor (human and AI agent)
must follow these patterns.

---

## 1. Typed Resource Functions

Every Terraform resource type is represented by a **typed resource function** in
its provider gem. The function:

1. Validates attributes via `Dry::Struct` (runtime type checking)
2. Synthesizes a Terraform resource block via `terraform-synthesizer`
3. Returns a `ResourceReference` for cross-resource composition

### Required Files Per Resource

```
lib/pangea/resources/<terraform_type>/
  resource.rb    # The typed function: def <terraform_type>(name, attributes = {})
  types.rb       # Dry::Struct attributes class with constraints
spec/resources/<terraform_type>/
  synthesis_spec.rb   # RSpec synthesis test (MANDATORY)
```

### Attribute Class Rules

- Inherit from `Pangea::Resources::BaseAttributes`
- Use `transform_keys(&:to_sym)` for symbol key normalization
- Use `Resources::Types::String`, `Resources::Types::Integer`, `Resources::Types::Bool`, etc.
- Use `.optional` for nullable fields, `.default(value.freeze)` for defaults
- Use `.constrained(...)` for format/range validation
- Override `self.new` for custom cross-field validation
- Always guard custom validation with `terraform_reference?` to allow `${...}` strings

### Terraform Reference Bypass

Infrastructure composition passes Terraform interpolation strings (`${...}`) as
attribute values. These MUST bypass type validation:

```ruby
def self.new(attributes = {})
  attrs = super(attributes)
  unless terraform_reference?(attrs.some_field)
    # Only validate when NOT a Terraform reference
    raise Dry::Struct::Error, "..." unless attrs.some_field.match?(PATTERN)
  end
  attrs
end
```

### Tags

Most AWS/Azure/GCP resources support tags. Handle them via the synthesizer block pattern:

```ruby
if attrs.tags&.any?
  tags do
    attrs.tags.each { |key, value| public_send(key, value) }
  end
end
```

Azure uses string-keyed tags: `Resources::Types::Hash.map(Resources::Types::String, Resources::Types::String)`
AWS uses symbol-keyed tags: `Resources::Types::AwsTags`

---

## 2. Typed Architecture Functions

Architectures compose multiple typed resource functions into reusable
infrastructure patterns. They live in `pangea-architectures`.

### Architecture Module Pattern

```ruby
module Pangea
  module Architectures
    module MyArchitecture
      def self.build(synth, config = {})
        # 1. Extend synthesizer with needed provider modules
        synth.extend(Pangea::Resources::AWS) unless synth.respond_to?(:aws_vpc)

        # 2. Validate required config
        name = config[:name] || raise(ArgumentError, ':name is required')

        # 3. Compose typed resources
        vpc = synth.aws_vpc(:main, { cidr_block: '10.0.0.0/16' })
        subnet = synth.aws_subnet(:public, { vpc_id: vpc.id, ... })

        # 4. Return resource reference map
        { vpc: vpc, subnet: subnet }
      end
    end
  end
end
```

### Architecture Registration

Register in `lib/pangea/architectures.rb`:

```ruby
autoload :MyArchitecture, 'pangea/architectures/my_architecture'
```

And add toggle in `build_all`:

```ruby
results[:my_arch] = MyArchitecture.build(synth, config) if config[:my_arch]
```

### Architecture Test Layers

1. **Synthesis spec** — validates Terraform JSON structure (zero cost)
2. **Security spec** — validates security invariants (no wildcards, least privilege)
3. **Integration spec** — validates cross-architecture composition

---

## 3. Type System

### Runtime (Current — Mandatory)

**dry-types + dry-struct** provide runtime type checking at synthesis time.

Core types (`pangea-core/lib/pangea/resources/types.rb`):
- `Resources::Types::String`, `::Integer`, `::Float`, `::Bool`, `::Hash`, `::Array`
- `Resources::Types::AwsTags` — `Hash.map(Types::Coercible::Symbol, Types::String)`
- Domain types: `CidrBlock`, `Port`, `Protocol`, `IpAddress`, `DomainName`

Constraints:
- `.constrained(format: /regex/)` — string format validation
- `.constrained(included_in: [...])` — enum validation
- `.constrained(gteq: n, lteq: m)` — range validation
- `.enum('value1', 'value2')` — enumerated values

### Static (Future — Incremental)

**RBS** signatures for pangea-core public API:
- Write `.rbs` files alongside Ruby source
- Run Steep in CI as non-blocking check
- Generate `.rbs` from pangea-forge for provider resources

**Do NOT** migrate to Sorbet `T::Struct`. The dry-struct integration is too deep
and the Terraform reference bypass pattern is incompatible with Sorbet.

---

## 4. Testing Standards

### Every Resource Must Have a Synthesis Spec

```ruby
RSpec.describe 'aws_<type>' do
  let(:synthesizer) { TerraformSynthesizer.new }

  it 'synthesizes with valid attributes' do
    synthesizer.instance_eval do
      extend Pangea::Resources::AWS
      aws_<type>(:test, { ... })
    end
    result = synthesizer.synthesis
    expect(result[:resource][:aws_<type>][:test]).to be_a(Hash)
  end

  it 'returns ResourceReference with correct outputs' do
    ref = synthesizer.instance_eval do
      extend Pangea::Resources::AWS
      aws_<type>(:test, { ... })
    end
    expect(ref).to be_a(Pangea::Resources::ResourceReference)
    expect(ref.outputs[:id]).to include('aws_<type>.test.id')
  end

  # Test Terraform reference support
  it 'accepts Terraform references in string fields' do
    synthesizer.instance_eval do
      extend Pangea::Resources::AWS
      aws_<type>(:test, { field: '${other.resource.id}', ... })
    end
    # Should not raise
  end

  # Test validation constraints
  it 'validates required fields' do
    expect {
      synthesizer.instance_eval do
        extend Pangea::Resources::AWS
        aws_<type>(:test, {})
      end
    }.to raise_error(Dry::Struct::Error)
  end
end
```

### Architecture Test Pyramid

| Layer | Location | What It Tests | Cost |
|-------|----------|---------------|------|
| Resource function | `pangea-aws/spec/resources/` | Single resource synthesis + validation | Zero |
| Architecture synthesis | `pangea-architectures/spec/architectures/` | Multi-resource composition | Zero |
| Architecture security | `pangea-architectures/spec/security/` | Least-privilege invariants | Zero |
| Architecture integration | `pangea-architectures/spec/integration/` | Cross-architecture composition | Zero |
| InSpec verification | `inspec-aws-k3s/controls/` | Live cloud state | Cloud API calls |

### Gated Workspace Pattern

`nix run .#plan` always runs the full RSpec suite before `terraform plan`.
Tests MUST pass before any infrastructure changes are applied.

---

## 5. Provider Gem Conventions

### Naming

| Gem | Module | Resource Prefix |
|-----|--------|-----------------|
| pangea-aws | `Pangea::Resources::AWS` | `aws_` |
| pangea-akeyless | `Pangea::Resources::Akeyless` | `akeyless_` |
| pangea-cloudflare | `Pangea::Resources::Cloudflare` | `cloudflare_` |
| pangea-gcp | `Pangea::Resources::Google` | `google_` |
| pangea-azure | `Pangea::Resources::Azure` | `azurerm_` |
| pangea-hcloud | `Pangea::Resources::Hcloud` | `hcloud_` |
| pangea-datadog | `Pangea::Resources::Datadog` | `datadog_` |
| pangea-splunk | `Pangea::Resources::Splunk` | `splunk_` |
| pangea-kubernetes | `Pangea::Resources::Kubernetes` | `kubernetes_` |

### Gemspec

```ruby
spec.add_dependency "pangea-core", "~> 0.2"
spec.add_dependency "terraform-synthesizer", "~> 0.0.28"
spec.add_dependency "dry-types", "~> 1.7"
spec.add_dependency "dry-struct", "~> 1.6"
spec.required_ruby_version = ">=3.3.0"
```

### Entry Point

`lib/pangea-<provider>.rb` requires all resource files:

```ruby
require_relative 'pangea/resources/aws_vpc/resource'
require_relative 'pangea/resources/aws_subnet/resource'
# ... all resources
```

---

## 6. Code Generation

Resources in `pangea-akeyless`, `pangea-cloudflare`, etc. are auto-generated by
`pangea-forge` from TOML resource specs + OpenAPI. Generated files have a header:

```ruby
# frozen_string_literal: true
# Copyright 2025 The Pangea Authors. Licensed under Apache 2.0.
# AUTO-GENERATED by pangea-forge — do not edit manually
```

Hand-written resources (common in `pangea-aws` for complex types) omit the
auto-generated comment. Both follow the same patterns.

---

## 7. Adding a New Resource

1. Create `lib/pangea/resources/<type>/types.rb` with `Dry::Struct` attributes
2. Create `lib/pangea/resources/<type>/resource.rb` with the typed function
3. Add `require_relative` to `lib/pangea-<provider>.rb`
4. Create `spec/resources/<type>/synthesis_spec.rb` with synthesis tests
5. Run `bundle exec rspec spec/resources/<type>/` to verify
6. Update CLAUDE.md resource count if applicable

---

## 8. Adding a New Architecture

1. Create `lib/pangea/architectures/<name>.rb` with `build(synth, config)` method
2. Add `synth.extend(...)` for all needed provider modules
3. Register in `lib/pangea/architectures.rb` (autoload + build_all toggle)
4. Create `spec/architectures/<name>_spec.rb` with synthesis tests
5. Create `spec/security/<name>_security_spec.rb` with security invariants
6. Run full suite: `bundle exec rspec`
