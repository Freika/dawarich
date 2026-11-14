# frozen_string_literal: true

require 'rails_helper'

RSpec.describe InsightsChartsHelper do
  describe '#donut_segments' do
    it 'turns shares into arcs that start at the top and add up to the whole' do
      segments = helper.donut_segments(home: 1, out: 1, trip: 1, untracked: 0)

      expect(segments.map(&:key)).to eq(%i[home out trip])
      expect(segments.sum(&:percent)).to eq(100)
      expect(segments.map(&:offset)).to eq([25.0, -8.33, -41.67])
    end

    it 'draws nothing when there is nothing to share' do
      expect(helper.donut_segments(home: 0, out: 0)).to be_empty
    end
  end
end
