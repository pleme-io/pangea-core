# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- Comprehensive README with usage examples and documentation
- CONTRIBUTING.md with development guidelines
- CHANGELOG.md for tracking version history

### Changed
- Updated license from MIT to Apache-2.0 for consistency
- Added copyright holder to LICENSE file

### Fixed
- License mismatch between gemspec and LICENSE file

## [0.0.27] - 2024-XX-XX

### Added
- Basic Terraform resource synthesis functionality
- Support for all standard Terraform configuration blocks:
  - terraform
  - provider  
  - resource
  - variable
  - locals
  - output
  - data
- Ruby DSL for programmatic Terraform configuration generation
- Test suite with RSpec
- Code quality enforcement with RuboCop
- Bundler gem configuration
- Nix development environment support

### Dependencies
- abstract-synthesizer gem dependency
- Development dependencies: rubocop, rspec, rake

## Previous Versions

Versions 0.0.1 through 0.0.26 contained iterative development of the core functionality and gem packaging improvements.