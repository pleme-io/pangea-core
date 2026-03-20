require %(abstract-synthesizer)

class TerraformSynthesizer < AbstractSynthesizer
  RESOURCE_KEYS = %i[
    terraform
    provider
    resource
    variable
    locals
    output
    data
  ].freeze

  def method_missing(method_name, ...)
    abstract_method_missing(
      method_name.to_sym,
      RESOURCE_KEYS,
      ...
    )
  end
end
