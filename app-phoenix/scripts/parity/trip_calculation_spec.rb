# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Phoenix fixture: a trip calculated by Rails' do
  def rows(sql, *binds)
    ActiveRecord::Base.connection.select_values(ActiveRecord::Base.sanitize_sql_array([sql, *binds])).map { JSON.parse(_1) }
  end

  it 'records the rows and the path, distance and countries Rails computes' do
    user = create(:user)
    user.update_columns(settings: user.settings.merge('minutes_between_routes' => '30'))
    source = PointSource.create!(tracker_id: 'watch', digest: 'fixture-digest-watch-00000000000')
    base = Time.utc(2026, 6, 1, 8).to_i
    now = Time.current
    phone = (0..60).reject { |i| (41..74).cover?(i) }.map do |i|
      { user_id: user.id, timestamp: base + (i * 60), tracker_id: 'phone', source_id: nil, anomaly: false,
        lonlat: "POINT(#{13.123455 + (i * 0.00001)} #{52.000005 + (i * 0.00001)})",
        country_name: i < 30 ? 'Germany' : 'Poland', created_at: now, updated_at: now }
    end
    watch = (15..45).map do |i|
      { user_id: user.id, timestamp: base + (i * 120) + 30, tracker_id: nil, source_id: source.id, anomaly: nil,
        lonlat: "POINT(#{14.000005 - (i * 0.00002)} #{50.123455 + (i * 0.00002)})",
        country_name: i == 20 ? nil : 'Czechia', created_at: now, updated_at: now }
    end
    extra = [
      { user_id: user.id, timestamp: base + 90, tracker_id: 'phone', source_id: nil, anomaly: true,
        lonlat: 'POINT(0 0)', country_name: 'Nowhere', created_at: now, updated_at: now },
      { user_id: user.id, timestamp: base + 90_000, tracker_id: 'phone', source_id: nil, anomaly: false,
        lonlat: 'POINT(1 1)', country_name: 'Later', created_at: now, updated_at: now }
    ]
    Point.insert_all(phone + watch + extra)
    trip = Trip.create!(
      user:, name: 'Fixture trip', started_at: Time.zone.at(base), ended_at: Time.zone.at(base + 5400),
      skip_calculation_enqueue: true
    )

    trip.calculate_path
    trip.calculate_distance
    trip.calculate_countries
    trip.save!

    expected_sql = <<~SQL.squish
      SELECT encode(ST_AsEWKB(path), 'hex') AS path_ewkb, distance,
             visited_countries::text AS visited_countries
      FROM trips WHERE id = ?
    SQL
    expected = ActiveRecord::Base.connection.select_one(ActiveRecord::Base.sanitize_sql_array([expected_sql, trip.id]))

    fixture = {
      'user' => rows(<<~SQL.squish, user.id).first,
        SELECT row_to_json(u)::text
        FROM (SELECT id, email, settings, created_at, updated_at FROM users WHERE id = ?) u
      SQL
      'point_sources' => rows('SELECT row_to_json(s)::text FROM point_sources s WHERE id = ?', source.id),
      'points' => rows('SELECT row_to_json(p)::text FROM points p WHERE user_id = ? ORDER BY id', user.id),
      'trip' => rows(<<~SQL.squish, trip.id).first,
        SELECT row_to_json(t)::text
        FROM (SELECT id, user_id, name, started_at, ended_at, created_at, updated_at FROM trips WHERE id = ?) t
      SQL
      'expected' => expected.merge('visited_countries' => JSON.parse(expected['visited_countries']))
    }

    path = Rails.root.join('app-phoenix/test/fixtures/trips/calculation.json')
    FileUtils.mkdir_p(path.dirname)
    File.write(path, "#{JSON.pretty_generate(fixture)}\n")
  end
end
