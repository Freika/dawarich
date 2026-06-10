# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Daily distance includes segments crossing midnight' do
  let(:user) { create(:user) }

  let(:departure) { Time.utc(2026, 5, 23, 23, 0) }

  before do
    [
      [[11.5820, 48.1351], departure],
      [[25.0000, 50.0000], departure + 50.minutes],
      [[116.4074, 39.9042], departure + 150.minutes]
    ].each do |(lon, lat), time|
      create(:point, user: user, timestamp: time.to_i, lonlat: "POINT(#{lon} #{lat})")
    end
  end

  def recalculate
    Stats::CalculateMonth.new(user.id, 2026, 5).call
    user.stats.find_by(year: 2026, month: 5)
  end

  def full_route_distance
    Point.connection.select_value(<<~SQL.squish).to_i
      SELECT ROUND(SUM(d)) FROM (
        SELECT ST_Distance(lonlat::geography, LAG(lonlat) OVER (ORDER BY timestamp)::geography) AS d
        FROM points WHERE user_id = #{user.id}
      ) segments
    SQL
  end

  it 'counts the segment that crosses midnight' do
    stat = recalculate
    day_24 = stat.daily_distance.to_h[24] || stat.daily_distance.to_h['24']

    expect(day_24).to be > 6_000_000
  end

  it 'sums the month to the full route distance' do
    stat = recalculate

    expect(stat.distance).to be_within(full_route_distance * 0.01).of(full_route_distance)
  end

  it 'still attributes the pre-midnight segment to the departure day' do
    stat = recalculate
    day_23 = stat.daily_distance.to_h[23] || stat.daily_distance.to_h['23']

    expect(day_23).to be_between(900_000, 1_100_000)
  end
end
