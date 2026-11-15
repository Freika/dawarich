# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Anomaly filtering preserves fast airliner cruise points' do
  let(:user) { create(:user, settings: { 'gps_filtering_enabled' => true }) }
  let(:base_time) { Time.utc(2024, 5, 10, 12).to_i }
  let(:cruise_start) { base_time + 1.day.to_i }

  # Entirely synthetic positions in the open Pacific, away from real places.
  # Slow readings dominate the month's speed sample.
  before do
    41.times do |index|
      create(:point, user: user, tracker_id: 'synthetic-phone', accuracy: 10,
                     timestamp: base_time + index * 60,
                     lonlat: "POINT(#{-140.0 + index * 0.00001} 0)")
    end
  end

  # One-second fixes on an equatorial great circle; 0.00285° a second is about 1,142 km/h.
  def cruise(step_degrees, count: 21)
    Array.new(count) do |index|
      create(:point, user: user, tracker_id: 'synthetic-phone', accuracy: 10,
                     timestamp: cruise_start + index,
                     lonlat: "POINT(#{-140.0 + index * step_degrees} 0)")
    end
  end

  def filter(until_time = cruise_start + 20)
    Points::AnomalyFilter.new(user.id, base_time, until_time).call
  end

  it 'keeps a straight cruise above 1,000 km/h in a month dominated by slow travel' do
    points = cruise(0.00285)

    meters = Point.connection.select_value(<<~SQL).to_f
      SELECT ST_Distance(first_fix.lonlat::geography, last_fix.lonlat::geography)
      FROM points first_fix, points last_fix
      WHERE first_fix.id = #{points.first.id} AND last_fix.id = #{points.last.id}
    SQL
    expect(meters / 20 * 3.6).to be_between(1_100, 1_200)

    filter

    expect(Point.where(id: points.map(&:id), anomaly: true)).to be_empty
  end

  it 'still flags a spike during the cruise' do
    points = cruise(0.00285)
    # Pushed 1.5 km ahead along the track, past the next fix: a detour.
    points[10].update_columns(lonlat: "POINT(#{-140.0 + (10 * 0.00285) + 0.0135} 0)")

    filter

    # Windows that end on the spike carry its detour, so the fixes either side
    # may be convicted with it; the rest of the cruise stays.
    flagged = Point.where(id: points.map(&:id), anomaly: true).pluck(:id)
    expect(flagged).to include(points[10].id)
    expect(flagged).to all(be_in(points[9..11].map(&:id)))
  end

  it 'still flags a sideways spike whose legs stay within airliner speed' do
    points = cruise(0.00285)
    # 400 m off the track: both legs about 1,800 km/h, so only the detour convicts.
    points[10].update_columns(lonlat: "POINT(#{-140.0 + (10 * 0.00285)} 0.0036)")

    filter

    flagged = Point.where(id: points.map(&:id), anomaly: true).pluck(:id)
    expect(flagged).to include(points[10].id)
    expect(flagged).to all(be_in(points[9..11].map(&:id)))
  end

  it 'still flags a steady straight run faster than any aircraft' do
    # About 3,600 km/h, one second apart.
    points = cruise(0.009, count: 3)

    filter(cruise_start + 2)

    expect(Point.where(id: points[1].id, anomaly: true)).to exist
  end
end
