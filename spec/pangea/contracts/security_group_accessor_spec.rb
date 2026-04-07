# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Pangea::Contracts::SecurityGroupAccessor do
  describe 'initialization' do
    it 'stores the security group ID' do
      accessor = described_class.new('sg-12345678')
      expect(accessor.id).to eq('sg-12345678')
    end

    it 'accepts terraform reference as ID' do
      accessor = described_class.new('${aws_security_group.main.id}')
      expect(accessor.id).to eq('${aws_security_group.main.id}')
    end

    it 'accepts nil as ID' do
      accessor = described_class.new(nil)
      expect(accessor.id).to be_nil
    end
  end
end

RSpec.describe Pangea::Contracts::ContractError do
  it 'inherits from StandardError' do
    expect(described_class.superclass).to eq(StandardError)
  end

  it 'can be raised and rescued' do
    expect {
      raise described_class, 'contract violation'
    }.to raise_error(described_class, 'contract violation')
  end
end
