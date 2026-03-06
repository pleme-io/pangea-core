# pangea-core

Core types, validation, and utilities for the Pangea infrastructure DSL.

## Overview

Provides the shared foundation for all Pangea provider gems: base resource types,
ResourceReference, ResourceRegistry, Dry::Struct type system, validation helpers,
entities, error types, logging, and network utilities. Every pangea-* provider gem
depends on this.

## Installation

```ruby
gem 'pangea-core', '~> 0.2'
```

## Usage

pangea-core is not used directly. It is a dependency of provider gems like
pangea-aws, pangea-cloudflare, and pangea-hcloud. It provides:

- `Pangea::Resources::Base` -- base class for all resource definitions
- `Pangea::Resources::ResourceReference` -- cross-resource reference tracking
- `Pangea::ResourceRegistry` -- global resource type registry
- `Pangea::Types` -- shared Dry::Types type definitions
- `Pangea::Validation` -- input validators (network, format)
- `Pangea::Entities` -- domain entity structs
- `Pangea::Logging` -- structured logging

## Development

```bash
nix develop
bundle exec rspec
```

## License

Apache-2.0
