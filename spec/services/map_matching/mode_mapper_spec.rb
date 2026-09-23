# frozen_string_literal: true

require 'rails_helper'

RSpec.describe MapMatching::ModeMapper do
  it 'maps supported Dawarich modes to Atlas costing modes' do
    expect(described_class.call(:walking)).to eq('pedestrian')
    expect(described_class.call(:running)).to eq('pedestrian')
    expect(described_class.call(:cycling)).to eq('bicycle')
    expect(described_class.call(:driving)).to eq('auto')
    expect(described_class.call(:bus)).to eq('auto')
    expect(described_class.call(:motorcycle)).to eq('auto')
  end

  it 'does not map modes Atlas should not match' do
    %i[unknown stationary train flying boat].each do |mode|
      expect(described_class.call(mode)).to be_nil
    end
  end
end
