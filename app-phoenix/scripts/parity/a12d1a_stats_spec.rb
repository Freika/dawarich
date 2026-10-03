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

RSpec.describe 'Phoenix fixture: A12d1b1 digest calculators' do
  include ActiveSupport::Testing::TimeHelpers

  let(:digest_now) { Time.utc(2026, 10, 3, 12) }
  let(:digest_uuid) { '00000000-0000-4000-8000-000000140500' }
  let(:digest_user_id) { 14_101 }

  it 'writes or matches the digest calculation corpus twice byte-identically' do
    expect(DawarichSettings.self_hosted?).to be(false)
    first = digest_capture
    expect(digest_capture).to eq(first)

    first.each do |relative, content|
      destination = Rails.root.join(relative)
      if ENV['WRITE_PHOENIX_FIXTURES'] == '1'
        FileUtils.mkdir_p(destination.dirname)
        File.write(destination, content)
      else
        expect(content).to eq(destination.read)
      end
    end
  end

  def digest_capture
    profiles = %w[berlin january previous_zero southern southern_alias missing_zone invalid_zone blank_zone
                  country_shapes malformed_json malformed_daily malformed_minutes ranked_locations
                  lite_partial lite_inherited
                  no_data old_data existing unchanged duplicates invalid_yearly invalid_month missing_user deleted_user
                  nil_mode missing_endpoint track_bounds]
    cases = profiles.flat_map do |profile|
      %w[monthly yearly].filter_map do |kind|
        next if %w[duplicates invalid_yearly].include?(profile) && kind == 'monthly'
        next if profile == 'invalid_month' && kind == 'yearly'

        digest_isolated { digest_case(profile, kind) }
      end
    end
    gaps = [[86_399, 0.1], [86_400, 0.1], [86_401, 0.1], [60, 0.099999], [60, 0.1], [60, 0.100001],
            [2400, 99.999999], [2400, 100], [2400, 100.000001], [2399, 100], [2401, 100],
            [86_400, 3600], [86_401, 3600], [0, 0], [-1, 0]]
    cases.concat(gaps.each_with_index.map do |gap, index|
      digest_isolated do
        digest_case("gap_#{index}", 'monthly', gap)
      end
    end)
    southern = Users::Digests::SeasonalityCalculator::TIMEZONE_LATITUDES.select do |_, latitude|
      latitude.negative?
    end.keys.sort
    {
      'app-phoenix/test/fixtures/a12d1b1/digests.json' => digest_json('version' => 1, 'cases' => cases),
      'app-phoenix/priv/digest_southern_zones.json' => digest_json(southern)
    }
  end

  def digest_json(value)
    "#{Oj.dump(value, mode: :strict, float_precision: 0, indent: 2)}\n"
  end

  def digest_isolated
    result = nil
    ActiveRecord::Base.transaction(requires_new: true) do
      travel_to(digest_now) { Time.use_zone('Europe/Berlin') { result = yield } }
      raise ActiveRecord::Rollback
    end
    result
  end

  def digest_case(profile, kind, gap = nil)
    digest_users(profile)
    year, month = profile == 'january' ? [2025, 1] : [2025, 3]
    month = 10 if %w[lite_partial lite_inherited].include?(profile)
    month = 13 if profile == 'invalid_month'
    digest_stats(profile, year, month)
    digest_points(profile, year, month) unless month == 13
    digest_tracks(profile, year, month, gap) unless month == 13
    digest_existing(profile, kind, year, month)
    if profile == 'unchanged'
      travel_to(digest_now - 1.day)
      digest_call(kind, year, month)
      travel_to(digest_now)
    end
    input = digest_input
    before = digest_rows
    result = nil
    error = nil
    begin
      result = digest_call(kind, year, month)
    rescue StandardError => e
      error = { 'class' => e.class.name, 'message' => e.message }
      error['details'] = e.record.errors.details.as_json if e.is_a?(ActiveRecord::RecordInvalid)
    end
    if %w[missing_user deleted_user].include?(profile)
      expect(error&.fetch('class')).to eq('ActiveRecord::RecordNotFound')
    end
    if profile == 'invalid_yearly'
      expect(error&.fetch('class')).to eq('ActiveRecord::RecordInvalid')
      expect(digest_rows).to eq(before)
    end
    expect(digest_rows).to eq(before) if profile == 'unchanged'
    expect(digest_rows.map { |row| row['id'] }).to eq([14_601]) if profile == 'duplicates'
    extra = gap ? digest_gap_oracle(year, month, gap) : {}
    {
      'id' => "#{profile}_#{kind}",
      'call' => { 'kind' => kind, 'user_id' => digest_user_id, 'year' => year,
                  'month' => kind == 'monthly' ? month : nil },
      'options' => { 'now' => digest_now.iso8601, 'ambient_zone' => 'Europe/Berlin',
                     'env' => { 'SELF_HOSTED' => 'false', 'TIME_ZONE' => 'Europe/Berlin' }, 'uuid' => digest_uuid },
      'legacy_duplicates' => profile == 'duplicates', 'null_segment_mode' => profile == 'nil_mode',
      'input' => input, 'before' => before,
      'expected' => { 'result_id' => result&.id, 'rows' => digest_rows, 'error' => error }.merge(extra)
    }
  end

  def digest_call(kind, year, month)
    ActiveRecord::Base.connection.execute("SELECT setval('digests_id_seq', 140500, false)")
    allow(SecureRandom).to receive(:uuid).and_return(digest_uuid)
    if kind == 'monthly'
      Users::Digests::CalculateMonth.new(digest_user_id, year, month).call
    else
      Users::Digests::CalculateYear.new(digest_user_id, year).call
    end
  end

  def digest_users(profile)
    settings = case profile
               when 'southern' then { 'timezone' => 'Australia/Sydney' }
               when 'southern_alias' then { 'timezone' => 'Sydney' }
               when 'missing_zone' then {}
               when 'invalid_zone' then { 'timezone' => 'Unknown/Zone' }
               when 'blank_zone' then { 'timezone' => '' }
               else { 'timezone' => 'Europe/Berlin' }
               end
    rows = [
      { id: digest_user_id, email: 'a12d1b1@example.invalid', encrypted_password: '', settings:, status: 1,
        plan: profile.start_with?('lite_') || profile == 'old_data' ? 0 : 1, active_until: nil,
        deleted_at: profile == 'deleted_user' ? digest_now : nil, created_at: digest_now, updated_at: digest_now },
      { id: 14_102, email: 'a12d1b1-other@example.invalid', encrypted_password: '', settings: {}, status: 1,
        plan: 2, active_until: digest_now + 1.year, deleted_at: nil, created_at: digest_now, updated_at: digest_now }
    ]
    rows.shift if profile == 'missing_user'
    User.unscoped.insert_all!(rows)
    return unless profile == 'lite_inherited'

    Family.insert_all!([{ id: 14_901, name: 'Synthetic family', creator_id: 14_102, access_until: nil,
                         created_at: digest_now, updated_at: digest_now }])
    Family::Membership.insert_all!([
                                     { id: 14_911, user_id: 14_102, family_id: 14_901, role: 0, created_at: digest_now,
                                       updated_at: digest_now },
                                     { id: 14_912, user_id: digest_user_id, family_id: 14_901, role: 1,
                                       created_at: digest_now,
                                       updated_at: digest_now }
                                   ])
  end

  def digest_stats(profile, year, month)
    return if %w[missing_user no_data].include?(profile)

    tops = [
      { 'country' => 'Germany',
        'cities' => [{ 'city' => 'Springfield', 'stayed_for' => '31minutes' },
                     { 'city' => 'Berlin', 'stayed_for' => 59.9 }] },
      { 'country' => 'France', 'cities' => [{ 'city' => 'Springfield', 'stayed_for' => nil }] },
      { 'country' => nil, 'cities' => [{ 'city' => 'Orphan city', 'stayed_for' => 3 }] },
      { 'country' => 'Country only', 'cities' => [] },
      { 'country' => 'Nonarray cities', 'cities' => nil }
    ]
    tops = { 'country' => 'Malformed', 'cities' => [] } if profile == 'malformed_json'
    tops.first['cities'].first['stayed_for'] = {} if profile == 'malformed_minutes'
    if profile == 'country_shapes'
      tops.concat([nil, 'not a hash', { 'country' => 12, 'cities' => [] },
                   { 'country' => 'Empty city', 'cities' => [nil, { 'city' => '' }, { 'city' => 2 }] },
                   [{ 'country' => 'Nested', 'cities' => [{ 'city' => 'Nested city' }] }]])
    end
    if profile == 'ranked_locations'
      tops = (0..10).map do |index|
        { 'country' => "Country #{10 - index}", 'cities' => [{ 'city' => "City #{index}", 'stayed_for' => 10 }] }
      end
    end
    previous_year, previous_month = month == 1 ? [year - 1, 12] : [year, month - 1]
    rows = [
      { id: 14_301, user_id: digest_user_id, year: year - 1, month: 1, distance: 7000,
        toponyms: [{ 'country' => 'Old', 'cities' => [{ 'city' => 'Old city' }] }] },
      { id: 14_302, user_id: digest_user_id, year: previous_year, month: previous_month,
        distance: profile == 'previous_zero' ? 0 : 20_000, toponyms: [{ 'country' => 'Previous', 'cities' => [] }] },
      { id: 14_303, user_id: digest_user_id, year:, month:, distance: 12_500, flight_distance: 425,
        daily_distance: profile == 'malformed_daily' ? 'invalid' : [[1, 12.5], %w[2 24], [3, 0]], toponyms: tops },
      { id: 14_304, user_id: 14_102, year:, month: 3, distance: 999_999,
        toponyms: [{ 'country' => 'Other', 'cities' => [{ 'city' => 'Other city' }] }] }
    ]
    if %w[lite_partial lite_inherited].include?(profile)
      rows << { id: 14_305, user_id: digest_user_id, year:, month: 1, distance: 7777,
                toponyms: [{ 'country' => 'Germany', 'cities' => [{ 'city' => 'Berlin' }] }] }
      rows << { id: 14_306, user_id: digest_user_id, year:, month: 12, distance: 12_500, toponyms: [] }
    end
    rows = rows.reject { |row| row[:user_id] == digest_user_id && row[:year] == year } if profile == 'old_data'
    Stat.insert_all!(rows.map do |row|
      { distance: 0, flight_distance: 0, daily_distance: {}, toponyms: [], h3_hex_ids: {}, calculation_version: 0,
        created_at: digest_now, updated_at: digest_now }.merge(row)
    end)
  end

  def digest_points(profile, year, month)
    return if profile == 'missing_user'

    first = Time.utc(year, month, 1)
    samples = [
      [first - 1800, 'Germany', false], [first + 600, 'France', false], [first + 3600, 'France', false],
      [first + 6.hours, 'Germany', true], [first + 12.hours, 'Germany', false], [first + 18.hours, nil, false],
      [Time.utc(year, month, 30, 1, 30), 'Germany', false]
    ]
    if month == 10
      samples.concat([[Time.utc(year, 10, 3, 11, 59, 59), 'Before cutoff', false],
                      [Time.utc(year, 10, 3, 12), 'At cutoff', true],
                      [Time.utc(year, 12, 31, 23, 30), 'Outside ambient year', false]])
    end
    if profile == 'ranked_locations'
      samples = (0..10).map { |index| [first + index * 60, "Country #{10 - index}", index == 10] }
    end
    Point.insert_all!(samples.each_with_index.map do |(at, country_name, anomaly), index|
      { id: 14_201 + index, user_id: digest_user_id, timestamp: at.to_i, lonlat: 'POINT(12 51)', country_name:,
        city: nil, velocity: '0', anomaly:, created_at: digest_now, updated_at: digest_now }
    end)
    Point.insert_all!([{ id: 14_250, user_id: 14_102, timestamp: first.to_i, lonlat: 'POINT(12 51)',
                        country_name: 'Other user', anomaly: false, created_at: digest_now, updated_at: digest_now }])
  end

  def digest_tracks(profile, year, month, gap)
    return if %w[missing_user no_data old_data].include?(profile)

    gap ||= [3600, 0]
    start = Time.utc(year, month, 4)
    starts = [start, start + 600 + gap[0]]
    if profile == 'track_bounds'
      starts.concat([Time.utc(year, month, 1) - 7200,
                     Time.utc(year, month, 1).end_of_month - 7200])
    end
    Track.insert_all!(starts.each_with_index.map do |at, index|
      { id: 14_401 + index, user_id: digest_user_id, start_at: at, end_at: at + 600,
        original_path: 'LINESTRING(0 0, 0.01 0)', created_at: digest_now, updated_at: digest_now }
    end)
    if profile == 'nil_mode'
      ActiveRecord::Base.connection.execute('ALTER TABLE track_segments ALTER COLUMN transportation_mode DROP NOT NULL')
    end
    TrackSegment.insert_all!(starts.each_with_index.map do |_, index|
      { id: 14_501 + index, track_id: 14_401 + index, start_index: 0, end_index: 1, duration: index.zero? ? 600 : 1800,
        transportation_mode: profile == 'nil_mode' && index == 1 ? nil : Track::TRANSPORTATION_MODES.fetch(:walking),
        created_at: digest_now, updated_at: digest_now }
    end)
    degrees = gap[1] / 6371.0 * 180 / Math::PI
    degrees = 1e-10 if gap == [0, 0]
    boundary = [
      { id: 14_260, track_id: 14_401, timestamp: (start + 600).to_i, lonlat: 'POINT(0 0)', anomaly: true },
      { id: 14_261, track_id: 14_402, timestamp: starts[1].to_i, lonlat: "POINT(#{degrees} 0)", anomaly: false }
    ]
    boundary.pop if profile == 'missing_endpoint'
    Point.insert_all!(boundary.map do |row|
      row.merge(user_id: digest_user_id, created_at: digest_now, updated_at: digest_now)
    end)
  end

  def digest_gap_oracle(year, month, gap)
    calculator = Users::Digests::ActivityBreakdownCalculator.new(User.find(digest_user_id), year, month)
    points = Point.where(id: [14_260, 14_261]).order(:id).to_a
    { 'gap' => { 'seconds' => gap[0], 'distance_km' => gap[1],
                 'classification' => calculator.send(:classify_gap_by_distance, *gap).as_json,
                 'geocoder_distance_km' => points.first.distance_to_geocoder(points.last, :km) } }
  end

  def digest_existing(profile, kind, year, month)
    return unless %w[existing duplicates invalid_yearly].include?(profile)

    if profile == 'duplicates'
      ActiveRecord::Base.connection.execute('DROP INDEX index_digests_on_user_year_period_type_monthless')
    end
    digest_month = kind == 'monthly' ? month : nil
    digest_month = 13 if profile == 'invalid_yearly'
    rows = [{ id: 14_601, user_id: digest_user_id, year:, month: digest_month,
              period_type: kind == 'monthly' ? 0 : 1, distance: 123, flight_distance: 999,
              sharing_uuid: '00000000-0000-4000-8000-000000014601', sharing_settings: { 'enabled' => true },
              sent_at: Time.utc(2026, 9, 1), created_at: Time.utc(2026, 8, 1), updated_at: Time.utc(2026, 9, 1) }]
    if profile == 'duplicates'
      rows << rows.first.merge(id: 14_602, distance: 456, flight_distance: 888,
                               sharing_uuid: '00000000-0000-4000-8000-000000014602',
                               sharing_settings: { 'enabled' => false })
    end
    Users::Digest.insert_all!(rows)
    expect(Users::Digest.where(user_id: digest_user_id, year:).count).to eq(2) if profile == 'duplicates'
  end

  def digest_input
    {
      'users' => digest_select('SELECT id, email, encrypted_password, settings, status, plan, active_until, ' \
                               'deleted_at, created_at, updated_at FROM users WHERE id IN (14101, 14102) ORDER BY id'),
      'families' => digest_select('SELECT * FROM families WHERE id = 14901 ORDER BY id'),
      'family_memberships' => digest_select('SELECT * FROM family_memberships WHERE id IN (14911, 14912) ORDER BY id'),
      'stats' => digest_select('SELECT * FROM stats WHERE user_id IN (14101, 14102) ORDER BY id'),
      'tracks' => digest_select('SELECT * FROM tracks WHERE user_id IN (14101, 14102) ORDER BY id'),
      'track_segments' => digest_select('SELECT * FROM track_segments ' \
                                       'WHERE track_id BETWEEN 14401 AND 14404 ORDER BY id'),
      'points' => digest_select('SELECT id, user_id, track_id, timestamp, lonlat, country_name, city, ' \
                                'velocity, anomaly, created_at, updated_at ' \
                                'FROM points WHERE user_id IN (14101, 14102) ORDER BY id'),
      'digests' => digest_rows
    }
  end

  def digest_rows
    digest_select('SELECT * FROM digests WHERE user_id IN (14101, 14102) ORDER BY id')
  end

  def digest_select(sql)
    ActiveRecord::Base.connection.select_values("SELECT row_to_json(x)::text FROM (#{sql}) x").map { |json| JSON.parse(json) }
  end
end
