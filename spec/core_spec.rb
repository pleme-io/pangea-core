# frozen_string_literal: true

require 'spec_helper'

RSpec.describe "PangeaCore" do
  it "has a version" do
    expect(PangeaCore::VERSION).to eq("0.1.0")
  end

  it "defines ResourceReference" do
    expect(defined?(Pangea::Resources::ResourceReference)).to eq("constant")
  end

  it "defines ResourceRegistry" do
    expect(defined?(Pangea::ResourceRegistry)).to eq("constant")
  end

  it "defines Base module" do
    expect(defined?(Pangea::Resources::Base)).to eq("constant")
  end

  it "defines Types module" do
    expect(defined?(Pangea::Resources::Types)).to eq("constant")
  end

  it "defines Helpers module" do
    expect(defined?(Pangea::Resources::Helpers)).to eq("constant")
  end
end
