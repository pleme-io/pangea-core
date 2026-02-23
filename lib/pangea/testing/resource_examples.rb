# frozen_string_literal: true

require 'rspec'

module Pangea
  module Testing
    # Shared RSpec examples for standard Pangea resource behavior.
    #
    # Usage in spec files:
    #
    #   RSpec.describe 'google_compute_network synthesis' do
    #     it_behaves_like 'a pangea resource',
    #       resource_type: :google_compute_network,
    #       provider: Pangea::Resources::Google,
    #       required_attrs: { name: 'test-vpc' },
    #       expected_outputs: [:id, :self_link]
    #
    #     # ... existing custom tests unchanged ...
    #   end
    #
    module ResourceExamples
      RSpec.shared_examples 'a pangea resource' do |resource_type:, provider:, required_attrs:, expected_outputs: [:id]|
        include Pangea::Testing::SynthesisTestHelpers

        let(:synth) { create_synthesizer }

        it 'creates terraform resource' do
          synth.extend(provider)
          synth.public_send(resource_type, :test, required_attrs)
          result = normalize_synthesis(synth.synthesis)
          config = result.dig('resource', resource_type.to_s, 'test')
          expect(config).not_to be_nil
        end

        it 'returns ResourceReference' do
          synth.extend(provider)
          ref = synth.public_send(resource_type, :test, required_attrs)
          expect(ref).to be_a(Pangea::Resources::ResourceReference)
          expect(ref.type).to eq(resource_type.to_s)
        end

        it 'has expected outputs' do
          synth.extend(provider)
          ref = synth.public_send(resource_type, :test, required_attrs)
          expected_outputs.each do |out|
            expect(ref.outputs).to have_key(out)
            expect(ref.outputs[out]).to eq("${#{resource_type}.test.#{out}}")
          end
        end
      end
    end
  end
end
