# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Trips::DayPathSql do
  let(:user) { create(:user) }
  let(:track) { create(:track, user:) }
  let(:points_scope) { user.points.not_anomaly }

  def record(time, longitude, track: self.track, **attributes)
    create(:point, user:, track:, timestamp: time.to_i, lonlat: "POINT(#{longitude} -40)", **attributes)
  end

  def day_paths(timezone: 'UTC', excluded_sql: nil, gap_seconds: 3600, track_id: track.id)
    builder = described_class.new(points_scope:, timezone:, gap_seconds:, excluded_sql:)
    sql = builder.sql(track_id_sql: track_id && ActiveRecord::Base.connection.quote(track_id))
    rows = ActiveRecord::Base.connection.select_all(
      "SELECT day::text AS day, ST_AsText((ST_Dump(path)).geom) AS wkt FROM (#{sql}) AS day_paths"
    ).to_a
    rows.group_by { |row| row['day'] }.sort.map { |day, parts| { day => parts.map { |part| part['wkt'] }.sort } }
  end

  it 'cuts a track at local midnight without joining the two days' do
    record(Time.utc(2026, 1, 1, 23, 0), -140.0)
    record(Time.utc(2026, 1, 1, 23, 30), -140.01)
    record(Time.utc(2026, 1, 2, 0, 30), -140.02)
    record(Time.utc(2026, 1, 2, 1, 0), -140.03)

    expect(day_paths).to eq([
                              { '2026-01-01' => ['LINESTRING(-140 -40,-140.01 -40)'] },
                              { '2026-01-02' => ['LINESTRING(-140.02 -40,-140.03 -40)'] }
                            ])
  end

  it 'breaks the line where a point is excluded instead of bridging it' do
    points = [-140.0, -140.01, -140.02, -140.03, -140.04].each_with_index.map do |longitude, index|
      record(Time.utc(2026, 1, 1, 10, index * 5), longitude)
    end

    paths = day_paths(excluded_sql: "points.id = #{points[2].id}")

    expect(paths).to eq([{ '2026-01-01' => ['LINESTRING(-140 -40,-140.01 -40)',
                                            'LINESTRING(-140.03 -40,-140.04 -40)'] }])
  end

  it 'draws day boundaries in the given timezone' do
    [10, 10.5, 11.2, 11.7].each_with_index do |hour, index|
      record(Time.utc(2026, 1, 1) + hour.hours, -140.0 - (index * 0.01))
    end

    expect(day_paths(timezone: 'UTC').flat_map(&:keys)).to eq(['2026-01-01'])
    expect(day_paths(timezone: 'Pacific/Auckland').flat_map(&:keys)).to eq(%w[2026-01-01 2026-01-02])
  end

  it 'joins points without a track and splits them at long gaps' do
    record(Time.utc(2026, 1, 1, 8, 0), -140.0, track: nil)
    record(Time.utc(2026, 1, 1, 8, 10), -140.01, track: nil)
    record(Time.utc(2026, 1, 1, 11, 0), -140.02, track: nil)
    record(Time.utc(2026, 1, 1, 11, 10), -140.03, track: nil)

    expected_parts = ['LINESTRING(-140 -40,-140.01 -40)', 'LINESTRING(-140.02 -40,-140.03 -40)']
    expect(day_paths(track_id: nil)).to eq([{ '2026-01-01' => expected_parts }])
  end

  it 'skips anomalies without breaking the line' do
    record(Time.utc(2026, 1, 1, 10, 0), -140.0)
    record(Time.utc(2026, 1, 1, 10, 5), -141.0, anomaly: true)
    record(Time.utc(2026, 1, 1, 10, 10), -140.02)

    expect(day_paths).to eq([{ '2026-01-01' => ['LINESTRING(-140 -40,-140.02 -40)'] }])
  end
end
