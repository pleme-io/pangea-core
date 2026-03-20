# -*- encoding: utf-8 -*-
# stub: terraform-synthesizer 0.0.28 ruby lib

Gem::Specification.new do |s|
  s.name = "terraform-synthesizer".freeze
  s.version = "0.0.28"

  s.required_rubygems_version = Gem::Requirement.new(">= 0".freeze) if s.respond_to? :required_rubygems_version=
  s.metadata = { "rubygems_mfa_required" => "true" } if s.respond_to? :metadata=
  s.require_paths = ["lib".freeze]
  s.authors = ["drzthslnt@gmail.com".freeze]
  s.date = "1980-01-01"
  s.description = "create terraform resources".freeze
  s.email = ["drzthslnt@gmail.com".freeze]
  s.homepage = "https://github.com/drzln/terraform-synthesizer".freeze
  s.licenses = ["Apache-2.0".freeze]
  s.required_ruby_version = Gem::Requirement.new(">= 3.3.0".freeze)
  s.rubygems_version = "3.3.26".freeze
  s.summary = "create terraform resources".freeze

  s.installed_by_version = "3.3.26" if s.respond_to? :installed_by_version

  if s.respond_to? :specification_version then
    s.specification_version = 4
  end

  if s.respond_to? :add_runtime_dependency then
    s.add_development_dependency(%q<rubocop>.freeze, [">= 0"])
    s.add_development_dependency(%q<rspec>.freeze, [">= 0"])
    s.add_development_dependency(%q<rake>.freeze, [">= 0"])
    s.add_runtime_dependency(%q<abstract-synthesizer>.freeze, [">= 0"])
  else
    s.add_dependency(%q<rubocop>.freeze, [">= 0"])
    s.add_dependency(%q<rspec>.freeze, [">= 0"])
    s.add_dependency(%q<rake>.freeze, [">= 0"])
    s.add_dependency(%q<abstract-synthesizer>.freeze, [">= 0"])
  end
end
