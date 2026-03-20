# Contributing to terraform-synthesizer

We love your input! We want to make contributing to terraform-synthesizer as easy and transparent as possible, whether it's:

- Reporting a bug
- Discussing the current state of the code
- Submitting a fix
- Proposing new features
- Becoming a maintainer

## Development Process

We use GitHub to host code, to track issues and feature requests, as well as accept pull requests.

### Pull Requests

Pull requests are the best way to propose changes to the codebase. We actively welcome your pull requests:

1. Fork the repo and create your branch from `main`.
2. If you've added code that should be tested, add tests.
3. If you've changed APIs, update the documentation.
4. Ensure the test suite passes.
5. Make sure your code lints.
6. Issue that pull request!

### Development Setup

1. Clone the repository:
   ```bash
   git clone https://github.com/drzln/terraform-synthesizer.git
   cd terraform-synthesizer
   ```

2. Install dependencies:
   ```bash
   bundle install
   ```

3. Run the tests:
   ```bash
   bundle exec rake spec
   ```

4. Run the linter:
   ```bash
   bundle exec rubocop
   ```

### Testing

- Write tests for any new functionality
- Ensure all existing tests pass
- Maintain or improve test coverage
- Use RSpec for testing following the existing patterns

### Code Style

- Follow Ruby style guidelines enforced by RuboCop
- Use meaningful variable and method names
- Add comments for complex logic
- Keep methods focused and concise

## Bug Reports

We use GitHub issues to track public bugs. Report a bug by opening a new issue.

**Great Bug Reports** tend to have:

- A quick summary and/or background
- Steps to reproduce
  - Be specific!
  - Give sample code if you can
- What you expected would happen
- What actually happens
- Notes (possibly including why you think this might be happening, or stuff you tried that didn't work)

## Feature Requests

We welcome feature requests! Please provide:

- Clear description of the feature
- Use case and motivation
- Examples of how it would work
- Any implementation ideas you might have

## Versioning

We use [Semantic Versioning](http://semver.org/). For the versions available, see the [tags on this repository](https://github.com/drzln/terraform-synthesizer/tags).

## License

By contributing, you agree that your contributions will be licensed under the Apache License 2.0.

## Questions?

Feel free to open an issue with the question label, or reach out to the maintainers directly.