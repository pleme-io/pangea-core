# frozen_string_literal: true

# Copyright 2025 The Pangea Authors
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

require 'json'

module Pangea
  # Abstract declaration of a named infrastructure architecture.
  #
  # An Architecture is "a named block of declarative infrastructure
  # that, when applied to a synthesizer, produces Terraform JSON". It
  # deliberately doesn't couple to any specific synthesizer — the
  # block is evaluated in whatever context ``apply`` is handed, so the
  # same Architecture could be re-rendered against a mock synthesizer
  # for tests, a dry-run synthesizer for plan preview, or a real
  # ``TerraformSynthesizer`` for apply.
  #
  # Example:
  #
  #   Pangea.architecture 'my_fleet' do
  #     resource :aws_vpc, 'main' do
  #       cidr_block '10.0.0.0/16'
  #       tags managed_tags
  #     end
  #   end
  #
  # The block reaches the synthesizer via ``apply`` below; attribute
  # method calls inside the ``resource`` block are interpreted by the
  # synthesizer's own method_missing (see terraform-synthesizer /
  # abstract-synthesizer for the DSL semantics).
  class Architecture
    attr_reader :name, :block

    def initialize(name, block)
      @name  = name
      @block = block
    end

    # Apply this architecture to a synthesizer. The block runs in the
    # synthesizer's context via ``instance_eval`` — every resource /
    # variable / output / etc. declared in the block is captured by
    # the synthesizer's normal method_missing pipeline.
    def apply(synth)
      synth.instance_eval(&@block)
      synth
    end
  end

  # Helper methods made available inside architecture blocks. Mixed
  # into TerraformSynthesizer at load time so the DSL can call things
  # like ``jsonencode(...)`` and ``managed_tags`` without caller-side
  # wiring. These are deliberately simple and free of side effects —
  # they return plain Ruby values the synthesizer can serialise.
  module TemplateHelpers
    # Serialise a Ruby hash/array to a JSON string. Matches the shape
    # Terraform's ``jsonencode(...)`` function produces; callers using
    # ``jsonencode({ Statement: [...] })`` get a string embedded into
    # the resource body, which Terraform then consumes verbatim.
    def jsonencode(value)
      JSON.generate(value)
    end

    # Canonical tag set applied to every Pangea-managed resource.
    # Consumers that want to extend (e.g. add team, cost-center,
    # environment) can ``merge`` their own hash on top.
    def managed_tags
      {
        ManagedBy: 'pangea',
        Namespace: ENV.fetch('PANGEA_NAMESPACE', 'default'),
      }
    end
  end

  # Class-level state for the DSL entry point. Each successful call to
  # ``Pangea.architecture`` stores the block here; the synthesizer's
  # ``capture_template_block`` reads this as a fallback to its older
  # ``template :name do ... end`` DSL, so both surfaces coexist.
  @architectures = {}
  @last_architecture = nil

  class << self
    # Register a named architecture and return its Architecture
    # instance. The block isn't executed here — only captured for
    # later ``apply`` by the synthesis machinery.
    #
    # @param name [String, Symbol] Human-facing name
    # @yield The architecture body (see Pangea::Architecture)
    # @return [Pangea::Architecture]
    def architecture(name, &block)
      raise ArgumentError, 'Pangea.architecture requires a block' unless block

      arch = Architecture.new(name.to_s, block)
      @architectures[name.to_s] = arch
      @last_architecture = arch
      arch
    end

    # Lookup by name — returns nil if unknown.
    def architecture_for(name)
      @architectures[name.to_s]
    end

    # Entire registry snapshot (caller gets a dup — the live map is
    # internal).
    def architectures
      @architectures.dup
    end

    # Most-recently-declared architecture. Used by the synthesizer to
    # fall back when no explicit ``template :name do`` block was
    # present in the template file.
    def last_architecture
      @last_architecture
    end

    # Reset the registry — primarily for tests that want a clean
    # starting state. Not part of the public DSL.
    def reset_architectures!
      @architectures = {}
      @last_architecture = nil
    end
  end
end

# Mix TemplateHelpers into TerraformSynthesizer when it's available.
# The ``defined?`` guard means pangea-core stays useful in contexts
# where only the abstract synthesizer (or a mock) is loaded — tests,
# CI preflight, etc.
if defined?(TerraformSynthesizer)
  TerraformSynthesizer.include(Pangea::TemplateHelpers)
end
