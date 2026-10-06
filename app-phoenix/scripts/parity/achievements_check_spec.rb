# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Phoenix fixture: achievement checks run by Rails' do
  include ActiveSupport::Testing::TimeHelpers

  around { |example| travel_to(Time.utc(2026, 10, 4, 22, 30)) { example.run } }

  def json_rows(sql, *binds)
    ActiveRecord::Base.connection.select_values(ActiveRecord::Base.sanitize_sql_array([sql, *binds]))
                      .map { JSON.parse(_1) }
  end

  def select_rows(sql, *binds)
    ActiveRecord::Base.connection.select_rows(ActiveRecord::Base.sanitize_sql_array([sql, *binds]))
  end

  def square(west, south, size)
    east = (west + size).round(4)
    north = (south + size).round(4)
    ring = [[west, south], [east, south], [east, north], [west, north], [west, south]]
    "SRID=4326;MULTIPOLYGON(((#{ring.map { _1.join(' ') }.join(', ')})))"
  end

  def insert_points!(user, country, lon, lat, first_timestamp, created_at, count: 9)
    rows = Array.new(count) do |i|
      { id: (@point_id = (@point_id || 81_300) + 1), user_id: user.id, timestamp: first_timestamp + (i * 300),
        lonlat: "POINT(#{lon} #{lat})",
        country_id: country.id, anomaly: false, created_at: created_at, updated_at: created_at }
    end
    ids = Point.insert_all(rows, returning: :id).rows.flatten
    json_rows('SELECT row_to_json(p)::text FROM points p WHERE id IN (?) ORDER BY id', ids)
  end

  def check!(user, notify, oldest)
    notify &&= Achievements::Progress.current_exploration.exists?(user_id: user.id)
    Achievements::RegionSetChecker.new(user, notify: notify, oldest_timestamp: oldest).call
  end

  def snapshot(user)
    state = JSON.parse(select_rows(
      "SELECT state::text FROM achievement_progresses WHERE user_id = ? AND achievement_key = 'exploration'", user.id
    ).dig(0, 0) || 'null')

    {
      'state' => state&.merge('earned' => state.fetch('earned', {}).keys.sort),
      'events' => select_rows('SELECT kind, key FROM achievement_unlock_events WHERE user_id = ?', user.id).sort,
      'awards' => select_rows('SELECT achievement_key FROM user_achievements WHERE user_id = ?', user.id).flatten.sort,
      'notifications' => select_rows('SELECT kind, title, content FROM notifications WHERE user_id = ?', user.id).sort
    }
  end

  it 'records four checks and the state, events, awards and notifications Rails writes after each' do
    Region.delete_all
    user = create(:user, id: 81_301, email: 'achievement-check-source@example.invalid')
    user.update_columns(settings: { 'locale' => 'de', 'min_minutes_spent_in_city' => 30 })
    Notification.where(user_id: user.id).delete_all

    de = Country.create!(id: 81_301, iso_a2: 'DE', iso_a3: 'DEU', name: 'Germany', geom: square(12.0, 51.0, 1.0))
    lu = Country.create!(id: 81_302, iso_a2: 'LU', iso_a3: 'LUX', name: 'Luxembourg', geom: square(6.0, 49.5, 0.3))
    corners = {
      'DE-SN' => [12.3, 51.3], 'DE-ST' => [12.1, 51.5], 'DE-TH' => [12.1, 51.1], 'DE-BB' => [12.5, 51.5],
      'DE-BE' => [12.7, 51.7], 'DE-MV' => [12.5, 51.8], 'DE-SH' => [12.1, 51.8], 'DE-HH' => [12.7, 51.1]
    }
    corners.each_with_index do |(code, (west, south)), index|
      Region.create!(id: 81_301 + index, code: code, geom: square(west, south, 0.1))
    end
    center = ->(code) { corners.fetch(code).map { |value| (value + 0.05).round(4) } }

    base = Time.utc(2026, 6, 1, 8).to_i
    step_one = insert_points!(user, de, 12.37, 51.34, base, Time.utc(2026, 6, 2, 10, 0, 0.5r), count: 12) +
               insert_points!(user, lu, 6.1, 49.6, base + 7200, Time.utc(2026, 6, 2, 10, 0, 0.5r))

    steps = []
    check!(user, true, nil)
    steps << { 'points' => step_one, 'anomaly_timestamps' => [], 'notify' => true, 'oldest' => nil,
               'expected' => snapshot(user) }

    step_two = insert_points!(user, de, *center.call('DE-ST'), base + 14_400, Time.utc(2026, 6, 3, 10, 0, 0.5r))
    check!(user, true, nil)
    steps << { 'points' => step_two, 'anomaly_timestamps' => [], 'notify' => true, 'oldest' => nil,
               'expected' => snapshot(user) }

    step_three = %w[DE-TH DE-BB DE-BE DE-MV DE-SH DE-HH].each_with_index.flat_map do |code, index|
      insert_points!(user, de, *center.call(code), base + 28_800 + (index * 7200), Time.utc(2026, 6, 4, 10))
    end
    check!(user, true, nil)
    steps << { 'points' => step_three, 'anomaly_timestamps' => [], 'notify' => true, 'oldest' => nil,
               'expected' => snapshot(user) }

    anomalies = step_two.map { _1['timestamp'] }
    Point.where(user_id: user.id, timestamp: anomalies).update_all(anomaly: true)
    check!(user, true, anomalies.min)
    steps << { 'points' => [], 'anomaly_timestamps' => anomalies, 'notify' => true, 'oldest' => anomalies.min,
               'expected' => snapshot(user) }

    fixture = {
      'user' => json_rows(<<~SQL.squish, user.id).first,
        SELECT row_to_json(u)::text
        FROM (SELECT id, email, settings, created_at, updated_at FROM users WHERE id = ?) u
      SQL
      'countries' => json_rows(<<~SQL.squish, [de.id, lu.id]),
        SELECT row_to_json(c)::text
        FROM (SELECT id, iso_a2, iso_a3, name, ST_AsEWKT(geom) AS geom, created_at, updated_at
              FROM countries WHERE id IN (?) ORDER BY id) c
      SQL
      'regions' => json_rows(<<~SQL.squish),
        SELECT row_to_json(r)::text
        FROM (SELECT id, code, ST_AsEWKT(geom) AS geom, created_at, updated_at FROM regions ORDER BY id) r
      SQL
      'steps' => steps
    }

    path = Rails.root.join('app-phoenix/test/fixtures/achievements/check.json')
    FileUtils.mkdir_p(path.dirname)
    bytes = "#{JSON.pretty_generate(fixture)}\n"
    if ENV['WRITE_PHOENIX_FIXTURES'] == '1'
      File.write(path, bytes)
    else
      expect(path.read).to eq(bytes)
    end
  end
end
