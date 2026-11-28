# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Daily distance with repeated stationary tower fixes' do
  let(:user) { create(:user, settings: { 'gps_filtering_enabled' => true }) }
  let(:started_at) { Time.utc(2026, 8, 6, 8) }
  let(:timespan) { Date.new(2026, 8, 1)..Date.new(2026, 8, 31) }

  def record_fix(latitude, minutes, accuracy: 10)
    # Invented coordinates in the open Pacific; no real location history.
    create(:point, user: user, longitude: -140.0, latitude: latitude,
                   timestamp: (started_at + minutes.minutes).to_i,
                   tracker_id: 'synthetic-android', accuracy: accuracy,
                   velocity: '0.0', vertical_accuracy: 0,
                   reverse_geocoded_at: started_at)
  end

  def daily_distance
    Stats::DailyDistanceQuery.new(
      user.points.not_anomaly, timespan, 'Etc/UTC', minutes_between_routes: 30
    ).call.to_h.fetch(6)
  end

  it 'keeps a three-kilometre walk near three kilometres after filtering tower bouncing' do
    # A short walk followed by a stationary stay.
    precise_fixes = 7.times.map { |i| record_fix(-40.0 + i * 0.0045, i * 5) }
    expect(daily_distance).to be_between(2_800, 3_200)

    # Repeated coarse fixes at the same position, about 5 km from the stay.
    # Android-style nonnegative motion fields do not carry iOS -1 sentinels.
    tower_fixes = 20.times.map do |i|
      tower = record_fix(-39.928, 35 + i * 10, accuracy: 1_200)
      precise_fixes << record_fix(-39.973, 40 + i * 10)
      tower
    end

    Points::AnomalyFilter.new(
      user.id, started_at.to_i, (started_at + 4.hours).to_i
    ).call

    aggregate_failures do
      expect(daily_distance).to be_between(2_800, 3_200)
      expect(tower_fixes.map { |point| point.reload.anomaly }).to all(be true)
      expect(precise_fixes.map { |point| point.reload.anomaly }).to all(be_falsey)
    end
  end
end
