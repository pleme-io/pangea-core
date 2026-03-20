# frozen_string_literal: true

lib = File.expand_path(%(lib), __dir__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require_relative %(lib/terraform-synthesizer/version)

Gem::Specification.new do |spec|
  spec.name                  = %(terraform-synthesizer)
  spec.version               = Meta::VERSION
  spec.authors               = [%(drzthslnt@gmail.com)]
  spec.email                 = [%(drzthslnt@gmail.com)]
  spec.description           = %(create terraform resources)
  spec.summary               = %(create terraform resources)
  spec.homepage              = %(https://github.com/drzln/#{spec.name})
  spec.license               = %(Apache-2.0)
  spec.require_paths         = [%(lib)]
  spec.required_ruby_version = %(>=3.3.0)

  spec.files = `git ls-files -z`.split("\x0").reject do |f|
    f.match(%r{^(test|spec|features)/})
  end

  %w[rubocop rspec rake].each do |dep|
    spec.add_development_dependency dep
  end

  %w[abstract-synthesizer].each do |dep|
    spec.add_dependency dep
  end

  spec.metadata['rubygems_mfa_required'] = 'true'
end
