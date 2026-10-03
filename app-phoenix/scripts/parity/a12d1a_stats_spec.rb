# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Phoenix fixture: A12d1a monthly statistics' do
  include ActiveSupport::Testing::TimeHelpers

  let(:path) { Rails.root.join('app-phoenix/test/fixtures/a12d1a/stats.json') }
  let(:now) { Time.utc(2026, 10, 3, 12) }
  let(:grid_sql) do
    'INSERT INTO points (id, user_id, timestamp, lonlat, anomaly, velocity, created_at, updated_at) ' \
      'SELECT 13000000 + g, $1::bigint, $2::int + g * 60, ' \
      'ST_SetSRID(ST_MakePoint(10.0 + (g % 101) * 0.02, 50.0 + (g / 101) * 0.02), 4326)::geography, ' \
      "false, '0', $3::text::timestamp, $3::text::timestamp FROM generate_series(0, 10099) AS g"
  end
  let(:case_ids) do
    %w[berlin_march_dst reset_keeps_flight margin_only_creates_month unchanged_row_untouched h3_fallback
       refresh_toponyms_tokyo]
  end

  it 'writes or matches stats.json, byte-identical on a second capture' do
    first = Oj.dump(capture, mode: :strict, float_precision: 0, indent: 2)
    expect(Oj.dump(capture, mode: :strict, float_precision: 0, indent: 2)).to eq(first)

    if ENV['WRITE_PHOENIX_FIXTURES'] == '1'
      FileUtils.mkdir_p(path.dirname)
      File.write(path, "#{first}\n")
    else
      expect("#{first}\n").to eq(path.read)
    end
  end

  def capture
    { 'version' => 1, 'cases' => case_ids.map { |id| isolated { { 'id' => id }.merge(send("case_#{id}")) } } }
  end

  def isolated
    result = nil
    ActiveRecord::Base.transaction(requires_new: true) do
      result = yield
      raise ActiveRecord::Rollback
    end
    result
  end

  def case_berlin_march_dst
    travel_to(now) do
      create(:country, id: 12_901, name: 'Germany', iso_a2: 'DE', iso_a3: 'DEU')
      create(:country, id: 12_902, name: 'Czechia', iso_a2: 'CZ', iso_a3: 'CZE')
      user!(12_101, { 'timezone' => 'Europe/Berlin', 'min_minutes_spent_in_city' => 30,
                      'minutes_between_routes' => '30' })
      user!(12_102, { 'timezone' => 'Etc/UTC' })
      imports!(12_101, 12_801 => 4, 12_802 => 5)
      leipzig = { city: 'Leipzig', country_name: 'Germany', country_id: 12_901 }
      halle = { city: 'Halle', country_name: 'Germany' }
      prague = { city: 'Prague', country_name: 'Czechia', country_id: 12_902, import_id: 12_802 }
      points!(12_101, [
                point(12_201, '2024-02-29 23:30', 12.3731, 51.3397, **leipzig, import_id: 12_801),
                point(12_202, '2024-03-01 00:10', 12.3781, 51.3407, **leipzig, country_name: 'Deutschland',
                                                                            import_id: 12_801),
                point(12_203, '2024-03-01 01:00', 12.3881, 51.3427, **leipzig, import_id: 12_801),
                point(12_204, '2024-03-01 02:00', 11.9697, 51.4825, **halle),
                point(12_205, '2024-03-01 02:00:30', 11.9797, 51.4835, **halle, velocity: '200'),
                point(12_206, '2024-03-01 02:01', 11.9897, 51.4845, **halle, velocity: '210'),
                point(12_207, '2024-03-01 02:05', 11.9707, 51.483, **halle),
                point(12_208, '2024-03-01 03:30', 11.9717, 51.4831, **halle),
                point(12_209, '2024-03-15 10:00', 14.4378, 50.0755, **prague),
                point(12_210, '2024-03-15 10:40', 14.44, 50.076, **prague),
                point(12_211, '2024-03-15 10:41', 14.8, 50.2, **prague),
                point(12_212, '2024-03-15 10:41', 14.441, 50.09, **prague),
                point(12_213, '2024-03-20 12:00', 12.3731, 51.3397, **leipzig, anomaly: true),
                point(12_214, '2024-03-31 01:30', 12.3741, 51.3398, **leipzig, import_id: 12_801),
                point(12_215, '2024-03-31 21:30', 12.3751, 51.3399, **leipzig, import_id: 12_801),
                point(12_216, '2024-03-31 22:30', 12.3761, 51.34, **leipzig, import_id: 12_801)
              ])
      flights!(12_101, [[12_701, 1, 123.456, Date.new(2024, 3, 10), nil],
                        [12_702, 2, 50.0, nil, Time.utc(2024, 3, 31, 23, 30)],
                        [12_703, 3, 75.25, Date.new(2024, 2, 28), nil]])
      flights!(12_102, [[12_704, 4, 999.0, Date.new(2024, 3, 12), nil]])
      input = snapshot([12_101, 12_102], [12_901, 12_902])
      Stats::CalculateMonth.new(12_101, 2024, 3).call
      kase(input, 'calculate', 12_101, 2024, 3)
    end
  end

  def case_reset_keeps_flight
    travel_to(now) do
      user!(12_103, { 'timezone' => 'Etc/UTC' })
      stats!(12_103, [[2024, 5, { distance: 500, daily_distance: [[1, 500]],
                                  toponyms: [{ 'country' => 'Germany', 'cities' => [] }],
                                  h3_hex_ids: [['881f1a8cb5fffff', 1, 1_714_521_600, 1_714_521_600]],
                                  calculation_version: 2 }, Time.utc(2026, 10, 1)]])
      flights!(12_103, [[12_705, 5, 10.5, Date.new(2024, 5, 5), nil]])
      input = snapshot([12_103])
      Stats::CalculateMonth.new(12_103, 2024, 5).call
      kase(input, 'calculate', 12_103, 2024, 5)
    end
  end

  def case_margin_only_creates_month
    travel_to(now) do
      user!(12_104, { 'timezone' => 'Etc/UTC' })
      points!(12_104, [point(12_217, '2024-06-30 23:00', 12.3731, 51.3397)])
      input = snapshot([12_104])
      Stats::CalculateMonth.new(12_104, 2024, 7).call
      kase(input, 'calculate', 12_104, 2024, 7)
    end
  end

  def case_unchanged_row_untouched
    leipzig = { city: 'Leipzig', country_name: 'Germany' }
    travel_to(Time.utc(2026, 10, 2, 12)) do
      user!(12_105, { 'timezone' => 'Etc/UTC', 'min_minutes_spent_in_city' => 0 })
      points!(12_105, [point(12_218, '2024-08-10 08:00', 12.3731, 51.3397, **leipzig),
                       point(12_219, '2024-08-10 08:10', 12.3745, 51.3402, **leipzig),
                       point(12_220, '2024-08-10 08:20', 12.376, 51.341, **leipzig)])
      Stats::CalculateMonth.new(12_105, 2024, 8).call
    end
    travel_to(now) do
      input = snapshot([12_105])
      Stats::CalculateMonth.new(12_105, 2024, 8).call
      kase(input, 'calculate', 12_105, 2024, 8)
    end
  end

  def case_h3_fallback
    travel_to(now) do
      user!(12_106, { 'timezone' => 'Etc/UTC' })
      params = [12_106, Time.utc(2024, 1, 1).to_i, '2026-10-03 12:00:00']
      ActiveRecord::Base.connection.exec_query(grid_sql, 'A12d1a grid', params)
      input = snapshot([12_106])
      Stats::CalculateMonth.new(12_106, 2024, 1).call
      kase(input, 'calculate', 12_106, 2024, 1).merge('generated_points' => { 'sql' => grid_sql, 'params' => params })
    end
  end

  def case_refresh_toponyms_tokyo
    travel_to(now) do
      create(:country, id: 12_901, name: 'Germany', iso_a2: 'DE', iso_a3: 'DEU')
      user!(12_107, { 'timezone' => 'Asia/Tokyo', 'min_minutes_spent_in_city' => 0 }, stats_swept_at: nil)
      stats!(12_107, [[2015, 1, {}, Time.utc(2026, 9, 30)], [2014, 12, {}, Time.utc(2026, 10, 1)]])
      leipzig = { city: 'Leipzig', country_name: 'Germany', country_id: 12_901 }
      halle = { city: 'Halle', country_name: 'Germany' }
      points!(12_107, [
                point(12_221, '2014-12-31 23:30', 12.3731, 51.3397, **leipzig),
                point(12_222, '2015-01-01 00:30', 12.3741, 51.3407, **leipzig),
                point(12_223, '2015-01-01 03:00', 11.9697, 51.4825, **halle),
                point(12_224, '2015-01-01 03:00:30', 11.99, 51.49, **halle, velocity: '300'),
                point(12_225, '2015-01-01 03:01', 12.01, 51.5, **halle, velocity: '300'),
                point(12_226, '2015-01-01 05:00', 11.9707, 51.4826, **halle),
                point(12_227, '2015-01-31 15:30', 12.3731, 51.3397, **leipzig)
              ])
      input = snapshot([12_107], [12_901])
      result = Stats::RefreshToponyms.new(User.find(12_107), 2015, 1).call
      swept = rows('SELECT id, stats_swept_at FROM users WHERE id IN (?)', [12_107]).first['stats_swept_at']
      kase(input, 'refresh', 12_107, 2015, 1, 'result' => result, 'stats_swept_at' => swept)
    end
  end

  def user!(id, settings, **attributes)
    create(:user, id:, email: "a12d1a-#{id}@example.invalid", settings:, **attributes)
  end

  def point(id, utc, lon, lat, **attributes)
    { id:, timestamp: Time.utc(*utc.scan(/\d+/).map(&:to_i)).to_i, lonlat: "POINT(#{lon} #{lat})", city: nil,
      country_name: nil, country_id: nil, import_id: nil, velocity: '0', anomaly: false }.merge(attributes)
  end

  def points!(user_id, rows)
    Point.insert_all!(rows.map { |row| row.merge(user_id:, created_at: now, updated_at: now) })
  end

  def imports!(user_id, sources)
    Import.insert_all!(sources.map do |id, source|
      { id:, user_id:, name: "a12d1a-#{id}", source:, created_at: now, updated_at: now }
    end)
  end

  def flights!(user_id, rows)
    Flight.insert_all!(rows.map do |id, external_id, distance_km, flight_date, departure_time|
      { id:, user_id:, external_id:, distance_km:, flight_date:, departure_time:, created_at: now, updated_at: now }
    end)
  end

  def stats!(user_id, rows)
    Stat.insert_all!(rows.map do |year, month, attributes, stamp|
      { user_id:, year:, month:, distance: 0, daily_distance: {}, flight_distance: 0, toponyms: [],
        h3_hex_ids: {}, calculation_version: 0, created_at: stamp, updated_at: stamp }.merge(attributes)
    end)
  end

  def snapshot(user_ids, country_ids = [0])
    {
      'countries' => rows('SELECT id, name, iso_a2, iso_a3, geom, created_at, updated_at FROM countries ' \
                          'WHERE id IN (?)', country_ids),
      'users' => rows("SELECT id, email, '' AS encrypted_password, settings, status, stats_swept_at, created_at, " \
                      'updated_at FROM users WHERE id IN (?)', user_ids),
      'imports' => rows('SELECT id, user_id, name, source, created_at, updated_at FROM imports WHERE user_id IN (?)',
                        user_ids),
      'points' => rows('SELECT id, user_id, timestamp, lonlat, city, country_name, country_id, velocity, anomaly, ' \
                       'import_id, created_at, updated_at FROM points WHERE user_id IN (?) AND id < 13000000',
                       user_ids),
      'flights' => rows('SELECT id, user_id, external_id, distance_km, flight_date, departure_time, created_at, ' \
                        'updated_at FROM flights WHERE user_id IN (?)', user_ids),
      'stats' => rows('SELECT user_id, year, month, distance, daily_distance, flight_distance, toponyms, ' \
                      'h3_hex_ids, calculation_version, created_at, updated_at, repair_deferred_at FROM stats ' \
                      'WHERE user_id IN (?)', user_ids)
    }
  end

  def rows(select, ids)
    sql = ActiveRecord::Base.sanitize_sql_array(["SELECT row_to_json(x)::text FROM (#{select} ORDER BY 1, 2) x", ids])
    ActiveRecord::Base.connection.select_values(sql).map { |json| JSON.parse(json) }
  end

  def stat_row(user_id, year, month)
    rows('SELECT year, month, distance, daily_distance, flight_distance, toponyms, h3_hex_ids, ' \
         "calculation_version, updated_at FROM stats WHERE user_id = #{user_id.to_i} AND year = #{year.to_i} " \
         "AND month = #{month.to_i} AND user_id IN (?)", [user_id]).first
  end

  def kase(input, kind, user_id, year, month, expected = {})
    { 'call' => { 'kind' => kind, 'user_id' => user_id, 'year' => year, 'month' => month }, 'input' => input,
      'expected' => { 'stat' => stat_row(user_id, year, month) }.merge(expected) }
  end
end
