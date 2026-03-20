# frozen_string_literal: true

lib = File.expand_path(%(lib), __dir__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require_relative %(lib/abstract-synthesizer/version)

Gem::Specification.new do |spec|
  spec.name                  = %(abstract-synthesizer)
  spec.version               = Meta::VERSION
  spec.authors               = [%(drzzln@protonmail.com)]
  spec.email                 = [%(drzzln@protonmail.com)]
  spec.description           = %(create resource based configuration DSL)
  spec.summary               = %(create resource based configuration DSL)
  spec.homepage              = %(https://github.com/drzln/#{spec.name})
  spec.license               = %(MIT)
  spec.require_paths         = [%(lib)]
  spec.required_ruby_version = %(>=3.3.0)

  spec.files = `git ls-files -z`.split("\x0").reject do |f|
    f.match(%r{^(test|spec|features)/})
  end

  %w[rspec rake rubocop].each do |dep|
    spec.add_development_dependency dep
  end

  spec.metadata['rubygems_mfa_required'] = 'true'
end
