# Contributing to Abstract Synthesizer

> **📋 Navigation**: [Main README](README.md) | [Overview](docs/overview.md) | [Usage Guide](docs/usage.md) | [Examples](examples/) | **Contributing**

Thank you for your interest in contributing to Abstract Synthesizer! We welcome contributions from everyone and appreciate your help in making this project better.

## Code of Conduct

Please note that this project is released with a Contributor Code of Conduct. By participating in this project you agree to abide by its terms.

## How to Contribute

### Reporting Issues

- Use the GitHub issue tracker to report bugs
- Describe the issue in detail, including steps to reproduce
- Include your Ruby version and gem version
- Provide a minimal test case if possible

### Submitting Changes

1. **Fork the repository** on GitHub
2. **Clone your fork** locally:
   ```bash
   git clone https://github.com/YOUR_USERNAME/abstract-synthesizer.git
   cd abstract-synthesizer
   ```
3. **Create a topic branch** for your changes:
   ```bash
   git checkout -b my-feature-branch
   ```
4. **Make your changes** following our coding standards
5. **Add tests** for your changes
6. **Run the test suite** to ensure nothing is broken:
   ```bash
   bundle exec rspec
   ```
7. **Run the linter**:
   ```bash
   bundle exec rubocop
   ```
8. **Commit your changes** with a descriptive commit message
9. **Push to your fork**:
   ```bash
   git push origin my-feature-branch
   ```
10. **Submit a pull request** on GitHub

## Development Setup

After cloning the repository:

```bash
# Install dependencies
bundle install

# Run tests
bundle exec rspec

# Run linter
bundle exec rubocop

# Run linter with auto-correct
bundle exec rubocop -a
```

## Coding Standards

- Follow Ruby community style guidelines
- Use RuboCop for code style consistency
- Write clear, descriptive commit messages
- Include tests for new functionality
- Update documentation for user-facing changes

## Testing

- Write tests for all new features and bug fixes
- Ensure all tests pass before submitting a pull request
- Use RSpec for testing
- Aim for good test coverage

## Documentation

- Update the README.md if you add new features
- Add or update code comments for complex functionality
- Consider adding examples to the docs/ directory

## Questions?

If you have questions about contributing, feel free to:

- Open an issue for discussion
- Ask questions in your pull request

We appreciate your contributions!

---

## 🔗 Project Resources

- **[Main README](README.md)** - Project overview and quick start
- **[Architecture Overview](docs/overview.md)** - Technical implementation details  
- **[Usage Guide](docs/usage.md)** - Comprehensive usage patterns
- **[Examples](examples/)** - Real-world examples and templates
- **[Issues](https://github.com/drzln/abstract-synthesizer/issues)** - Bug reports and feature requests
- **[Pull Requests](https://github.com/drzln/abstract-synthesizer/pulls)** - Code contributions

## 💡 Contribution Ideas

- **Examples**: Add DSLs for new domains (monitoring, security, networking, etc.)
- **Documentation**: Improve guides, add tutorials, create video content
- **Testing**: Increase test coverage, add performance benchmarks
- **Features**: Enhance validation, add new output formats, improve error messages
- **Ecosystem**: Create integrations with popular Ruby frameworks and tools