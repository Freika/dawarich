# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Daily distance includes segments crossing midnight' do
  let(:user) { create(:user) }

  let(:departure) { Time.utc(2026, 5, 23, 22, 0) }
  let(:import) { create(:import, user: user, source: 'gpx') }

  before do
    [
      [[11.5820, 48.1351], departure],
      [[25.0000, 50.0000], departure + 90.minutes],
      [[116.4074, 39.9042], departure + 10.hours]
    ].each do |(lon, lat), time|
      create(:point, user: user, import: import, timestamp: time.to_i, lonlat: "POINT(#{lon} #{lat})")
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

  [Time.utc(2026, 6, 1), Time.utc(2027, 1, 1)].each do |boundary|
    it "counts a realistic imported segment across #{boundary.strftime('%Y-%m')}" do
      create(:point, user: user, import: import, lonlat: 'POINT(13.40 52.50)', timestamp: (boundary - 10.minutes).to_i)
      create(:point, user: user, import: import, lonlat: 'POINT(13.41 52.51)', timestamp: (boundary + 10.minutes).to_i)

      Stats::CalculateMonth.new(user.id, boundary.year, boundary.month).call

      stat = user.stats.find_by!(year: boundary.year, month: boundary.month)
      expect(stat.daily_distance.to_h[1] || stat.daily_distance.to_h['1']).to be_between(1_200, 1_400)
    end
  end

  [1, 2].each do |version|
    it "schedules repair for historical calculation version #{version}" do
      user.points.update_all(created_at: 1.day.ago)
      user.update_column(:stats_swept_at, Time.current)
      create(:stat, user: user, year: 2026, month: 5, calculation_version: version)
        .update_column(:updated_at, 1.day.ago)

      expect { Stats::BulkCalculator.new(user.id).call }
        .to have_enqueued_job(Stats::CalculatingJob).with(user.id, 2026, 5, notify_on_failure: false)
    end
  end
end
