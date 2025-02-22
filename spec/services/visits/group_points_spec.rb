# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Visits::GroupPoints do
  describe '#group_points_by_radius' do
    it 'groups points by radius' do
      day_points = [
        build(:point, lonlat: 'POINT(0 0)', timestamp: 1.day.ago),
        build(:point, lonlat: 'POINT(0.00001 0.00001)', timestamp: 1.day.ago + 1.minute),
        build(:point, lonlat: 'POINT(0.00002 0.00002)', timestamp: 1.day.ago + 2.minutes),
        build(:point, lonlat: 'POINT(0.00003 0.00003)', timestamp: 1.day.ago + 3.minutes),
        build(:point, lonlat: 'POINT(0.00004 0.00004)', timestamp: 1.day.ago + 4.minutes),
        build(:point, lonlat: 'POINT(0.00005 0.00005)', timestamp: 1.day.ago + 5.minutes),
        build(:point, lonlat: 'POINT(0.00006 0.00006)', timestamp: 1.day.ago + 6.minutes),
        build(:point, lonlat: 'POINT(0.00007 0.00007)', timestamp: 1.day.ago + 7.minutes),
        build(:point, lonlat: 'POINT(0.00008 0.00008)', timestamp: 1.day.ago + 8.minutes),
        build(:point, lonlat: 'POINT(0.00009 0.00009)', timestamp: 1.day.ago + 9.minutes),
        build(:point, lonlat: 'POINT(0.001 0.001)', timestamp: 1.day.ago + 10.minutes)
      ]

      grouped_points = described_class.new(day_points).group_points_by_radius

      expect(grouped_points.size).to eq(1)
      expect(grouped_points.first.size).to eq(10)
      # The last point is too far from the first point
      expect(grouped_points.first).not_to include(day_points.last)
    end
  end
end
