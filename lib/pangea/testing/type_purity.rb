# frozen_string_literal: true

require 'rspec'

module Pangea
  module Testing
    # Shared RSpec examples and helpers for proving type purity across
    # ALL Pangea provider gems. Include in any provider spec to validate:
    #
    #   - All types inherit BaseAttributes (not Dry::Struct)
    #   - No T::Ref unions in generated types
    #   - ResourceInput handles refs at the serialization boundary
    #   - Literal values are validated strictly per-field
    #   - Required coverage enforced for ref-carrying fields
    #
    # Usage:
    #   RSpec.describe 'pangea-porkbun type purity' do
    #     it_behaves_like 'a pure typed provider',
    #       provider_module: Pangea::Resources::Porkbun,
    #       types_module: Pangea::Resources::Porkbun::Types,
    #       lib_path: File.expand_path('../../lib', __dir__)
    #   end
    #
    module TypePurity
      # ── Helper: scan a provider's lib/ for type violations ────────

      # Scan all types.rb files under a path and return violations.
      # @param lib_path [String] Absolute path to the provider's lib/ directory
      # @return [Hash] { base_attributes: [paths], dry_struct: [paths], ref_unions: [paths] }
      def self.audit_types(lib_path)
        types_files = Dir.glob(File.join(lib_path, '**', 'types.rb'))
        result = { base_attributes: [], dry_struct: [], ref_unions: [] }

        types_files.each do |f|
          content = File.read(f)
          rel = f.sub("#{lib_path}/", '')

          if content.include?('< Pangea::Resources::BaseAttributes')
            result[:base_attributes] << rel
          elsif content.include?('< Dry::Struct')
            result[:dry_struct] << rel
          end

          if content.match?(/\| T::Ref\b/)
            result[:ref_unions] << rel
          end
        end

        result
      end

      # ── Helper: collect all attribute classes from a Types module ──

      # Find all Dry::Struct subclasses in a types module.
      # @param types_module [Module] e.g. Pangea::Resources::Porkbun::Types
      # @return [Array<Class>] Attribute classes
      def self.attribute_classes(types_module)
        types_module.constants(false)
          .map { |c| types_module.const_get(c) }
          .select { |c| c.is_a?(Class) && c < Dry::Struct }
      end

      # ── Shared Examples ───────────────────────────────────────────

      RSpec.shared_examples 'a pure typed provider' do |provider_module:, types_module:, lib_path:|
        describe 'type purity' do
          let(:audit) { TypePurity.audit_types(lib_path) }
          let(:attr_classes) { TypePurity.attribute_classes(types_module) }

          it 'has NO Dry::Struct inheritance (all types use BaseAttributes)' do
            expect(audit[:dry_struct]).to be_empty,
              "#{audit[:dry_struct].length} types still inherit Dry::Struct:\n" \
              "#{audit[:dry_struct].join("\n")}"
          end

          it 'has at least one BaseAttributes type' do
            expect(audit[:base_attributes]).not_to be_empty,
              'No BaseAttributes types found — provider may not be generated'
          end

          it 'has NO T::Ref union types (refs handled at serialization boundary)' do
            expect(audit[:ref_unions]).to be_empty,
              "#{audit[:ref_unions].length} types contain | T::Ref unions:\n" \
              "#{audit[:ref_unions].join("\n")}"
          end

          it 'all attribute classes inherit BaseAttributes' do
            non_base = attr_classes.reject { |c| c < Pangea::Resources::BaseAttributes }
            expect(non_base).to be_empty,
              "#{non_base.length} classes don't inherit BaseAttributes: #{non_base.map(&:name).join(', ')}"
          end
        end
      end

      # ── Shared Examples: ResourceInput integration ────────────────

      RSpec.shared_examples 'ResourceInput handles refs for' do |attributes_class:, literal_attrs:, ref_attr:, ref_value: '${aws_test.x.id}'|
        describe "ResourceInput with #{attributes_class}" do
          let(:all_attrs) { literal_attrs.merge(ref_attr => ref_value) }
          let(:input) { Pangea::Resources::ResourceInput.partition(attributes_class, all_attrs) }

          it 'partitions ref from literals' do
            expect(input.refs).to have_key(ref_attr)
            expect(input.refs[ref_attr]).to eq(ref_value)
          end

          it 'validates literals strictly' do
            input # should not raise
            literal_attrs.each do |k, _v|
              expect(input.validated.to_h).to have_key(k)
            end
          end

          it '[] resolves ref over literal' do
            expect(input[ref_attr]).to eq(ref_value)
          end

          it 'to_h includes both literals and refs' do
            h = input.to_h
            literal_attrs.each { |k, v| expect(h[k]).to eq(v) }
            expect(h[ref_attr]).to eq(ref_value)
          end

          it 'is frozen' do
            expect(input).to be_frozen
            expect(input.refs).to be_frozen
          end
        end
      end
    end
  end
end
