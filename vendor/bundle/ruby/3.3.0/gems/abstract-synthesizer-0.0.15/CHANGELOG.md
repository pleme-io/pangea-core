# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- Enhanced README with comprehensive usage examples and documentation
- CONTRIBUTING.md with development guidelines
- CHANGELOG.md for tracking project changes

### Removed
- GEMINI.md files (replaced with Claude-based development)
- Built gem artifacts from pkg/ directory
- Exposed API key from .envrc file

### Security
- Removed exposed API key from version control

## [0.0.14] - 2023-XX-XX

### Added
- Core DSL functionality for resource-based configuration
- SynthesizerFactory for creating configured synthesizer instances
- Error handling with InvalidSynthesizerKeyError and TooManyFieldValuesError
- Hierarchical configuration support with nested resources
- Field assignment validation

### Features
- Dynamic method creation based on provided resource keys
- Flexible argument handling for resource definitions
- Context-aware field processing
- Built-in manifest generation and access

## Previous Versions

Previous versions (0.0.4 through 0.0.13) included iterative development of the core DSL functionality and error handling systems.