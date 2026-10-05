# frozen_string_literal: true

require 'rails_helper'
require 'sidekiq/cron/job'

RSpec.describe 'Phoenix fixture: A12d1a monthly statistics' do
  include ActiveSupport::Testing::TimeHelpers

  before { allow(DawarichSettings).to receive(:self_hosted?).and_return(false) }

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

  before { allow(DawarichSettings).to receive(:self_hosted?).and_return(false) }

  let(:digest_now) { Time.utc(2026, 10, 3, 12) }
  let(:digest_uuid) { '00000000-0000-4000-8000-000000140500' }
  let(:digest_user_id) { 14_101 }

  it 'digest captures preserve sequence state after rollback and an escaping error' do
    connection = ActiveRecord::Base.connection
    %w[digests stats].each do |table|
      statement = "SELECT last_value, is_called FROM #{table}_id_seq"
      original = connection.select_one(statement)
      digest_isolated { connection.execute("SELECT setval('#{table}_id_seq', 42, false)") }
      expect(connection.select_one(statement)).to eq(original)
      expect do
        digest_isolated do
          connection.execute("SELECT setval('#{table}_id_seq', 43, true)")
          raise 'capture failure'
        end
      end.to raise_error('capture failure')
      expect(connection.select_one(statement)).to eq(original)
    end
  end

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
                  country_shapes malformed_json malformed_daily false_daily malformed_minutes ranked_locations
                  lite_partial lite_inherited
                  no_data old_data existing unchanged duplicates invalid_yearly invalid_month missing_user deleted_user
                  nil_mode missing_endpoint track_bounds default_ambient]
    cases = profiles.flat_map do |profile|
      %w[monthly yearly].filter_map do |kind|
        next if %w[duplicates invalid_yearly].include?(profile) && kind == 'monthly'
        next if profile == 'invalid_month' && kind == 'yearly'
        next if profile == 'default_ambient' && kind == 'monthly'
        next if profile == 'false_daily' && kind == 'yearly'

        digest_isolated(profile) { digest_case(profile, kind) }
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
    "#{Oj.dump(value, mode: :strict, float_precision: 0, indent: 2).chomp}\n"
  end

  def digest_isolated(profile = nil)
    result = nil
    connection = ActiveRecord::Base.connection
    sequences = %w[digests stats].index_with do |table|
      connection.select_one("SELECT last_value, is_called FROM #{table}_id_seq")
    end
    zone = profile == 'default_ambient' ? Rails.application.config.time_zone : 'Europe/Berlin'
    if profile == 'default_ambient'
      expect(ENV).not_to have_key('TIME_ZONE')
      expect(zone).to eq('Europe/Berlin')
    end
    ActiveRecord::Base.transaction(requires_new: true) do
      travel_to(digest_now) { Time.use_zone(zone) { result = yield } }
      raise ActiveRecord::Rollback
    end
    result
  ensure
    sequences&.each do |table, state|
      connection.execute("SELECT setval('#{table}_id_seq', #{state.fetch('last_value')}, " \
                         "#{connection.quote(state.fetch('is_called'))})")
    end
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
    options = { 'now' => digest_now.iso8601, 'ambient_zone' => 'Europe/Berlin',
                'env' => { 'SELF_HOSTED' => 'false',
                           'TIME_ZONE' => Users::SafeSettings::DEFAULT_VALUES.fetch('timezone') },
                'uuid' => digest_uuid }
    if profile == 'default_ambient'
      options.delete('ambient_zone')
      options['env'].delete('TIME_ZONE')
    end
    {
      'id' => "#{profile}_#{kind}",
      'call' => { 'kind' => kind, 'user_id' => digest_user_id, 'year' => year,
                  'month' => kind == 'monthly' ? month : nil },
      'options' => options,
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
               when 'missing_zone', 'default_ambient' then {}
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
    daily_distance = case profile
                     when 'malformed_daily' then 'invalid'
                     when 'false_daily' then false
                     else [[1, 12.5], %w[2 24], [3, 0]]
                     end
    rows = [
      { id: 14_301, user_id: digest_user_id, year: year - 1, month: 1, distance: 7000,
        toponyms: [{ 'country' => 'Old', 'cities' => [{ 'city' => 'Old city' }] }] },
      { id: 14_302, user_id: digest_user_id, year: previous_year, month: previous_month,
        distance: profile == 'previous_zero' ? 0 : 20_000, toponyms: [{ 'country' => 'Previous', 'cities' => [] }] },
      { id: 14_303, user_id: digest_user_id, year:, month:, distance: 12_500, flight_distance: 425,
        daily_distance:, toponyms: tops },
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
    if profile == 'default_ambient'
      samples.concat([[Time.utc(year - 1, 12, 31, 23, 30), 'Inside ambient year', false],
                      [Time.utc(year, 12, 31, 23, 30), 'Outside ambient year', false]])
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

  it 'writes or matches the digest job corpus twice byte-identically' do
    first = digest_job_capture
    expect(digest_job_capture).to eq(first)
    destination = Rails.root.join('app-phoenix/test/fixtures/a12d1b2/jobs.json')
    if ENV['WRITE_PHOENIX_FIXTURES'] == '1'
      FileUtils.mkdir_p(destination.dirname)
      File.write(destination, first)
    else
      expect(first).to eq(destination.read)
    end
  end

  def digest_job_capture
    schedulers = %w[monthly yearly].flat_map do |kind|
      [
        ['january', '2025-01-01T23:30:00Z', 'Europe/Berlin'],
        ['march', '2024-03-31T22:30:00Z', 'Europe/Berlin'],
        ['leap_day', '2024-02-29T23:30:00Z', 'Asia/Tokyo'],
        ['end_month', '2025-03-31T12:00:00Z', 'Etc/UTC'],
        ['zone_boundary', '2025-01-31T23:30:00Z', 'Asia/Tokyo'],
        ['two_batches', '2025-04-02T04:00:00Z', 'Europe/Berlin']
      ].map do |id, instant, zone|
        RSpec::Mocks.with_temporary_scope do
          digest_job_isolated { digest_job_scheduler(kind, id, instant, zone) }
        end
      end
    end
    workers = %w[monthly yearly].flat_map do |kind|
      %w[new existing no_data missing_user deleted_user stats_return stats_database stats_raise
         digest_raise digest_database late_stats_raise vanished year_boundary].flat_map do |profile|
        next [] if %w[late_stats_raise year_boundary].include?(profile) && kind == 'monthly'

        %w[en fr].map do |locale|
          RSpec::Mocks.with_temporary_scope do
            digest_isolated { digest_job_worker(kind, profile, locale) }
          end
        end
      end
    end
    digest_json('version' => 1, 'schedulers' => schedulers, 'workers' => workers,
                'toggles' => digest_job_toggles, 'triggers' => digest_job_triggers)
  end

  def digest_job_toggles
    values = [false, true, nil, '', 0, 1, '0', 'f', 'F', 'false', 'FALSE', 'off', 'OFF', 'yes', [], {}]
    settings = [{}] + values.flat_map do |value|
      [{ 'value' => value }, { 'digest_emails_enabled' => value },
       { 'value' => value, 'digest_emails_enabled' => true },
       { 'value' => value, 'digest_emails_enabled' => false }]
    end
    %w[monthly yearly].flat_map do |kind|
      key = "#{kind}_digest_emails_enabled"
      settings.map do |item|
        item = item.transform_keys { |name| name == 'value' ? key : name }
        { 'kind' => kind, 'settings' => item,
          'enabled' => Users::SafeSettings.new(item).public_send("#{key}?") }
      end
    end
  end

  def digest_job_isolated
    result = nil
    ActiveRecord::Base.transaction(requires_new: true) do
      result = yield
      raise ActiveRecord::Rollback
    end
    result
  end

  def digest_job_scheduler(kind, id, instant, zone)
    uuid_index = 151_000
    allow(SecureRandom).to receive(:uuid) do
      uuid_index += 1
      format('00000000-0000-4000-8000-%012d', uuid_index)
    end
    travel_to(Time.iso8601(instant)) do
      Time.use_zone(zone) do
        target = kind == 'monthly' ? 1.month.ago : 1.year.ago
        cases = [
          [1, {}, target.year, target.month, nil],
          [2, { 'timezone' => 'America/Los_Angeles', 'locale' => ' FR ' }, target.year, target.month, nil],
          [0, {}, target.year, target.month, nil], [3, {}, target.year, target.month, nil],
          [1, {}, target.year, target.month, digest_now], [1, {}, nil, nil, nil],
          [1, {}, target.year - 1, target.month, nil],
          [1, {}, target.year, target.month == 12 ? 1 : target.month + 1, nil]
        ]
        cases.concat(digest_job_toggles.select { |row| row['kind'] == kind }.map do |row|
          [1, row['settings'], target.year, target.month, nil]
        end)
        cases.concat(Array.new(1001) { [1, {}, target.year, target.month, nil] }) if id == 'two_batches'
        users = cases.each_with_index.map do |(status, settings, _, _, deleted_at), index|
          { id: 15_101 + index, email: "a12d1b2-#{index}@example.invalid", encrypted_password: '',
            status:, settings:, plan: 0, deleted_at:, created_at: digest_now, updated_at: digest_now }
        end
        User.unscoped.insert_all!(users)
        stats = cases.each_with_index.filter_map do |(_, _, year, month, _), index|
          next unless year

          { id: 16_501 + index, user_id: users[index][:id], year:, month:, distance: 0,
            daily_distance: {}, toponyms: [], created_at: digest_now, updated_at: digest_now }
        end
        Stat.insert_all!(stats)
        clear_enqueued_jobs
        klass = digest_job_class(kind, 'SchedulingJob')
        klass.new.perform
        jobs = digest_job_enqueued
        expected_ids = cases.each_with_index.filter_map do |(status, settings, year, month, deleted), index|
          next unless [1, 2].include?(status) && deleted.nil? && year == target.year
          next if kind == 'monthly' && month != target.month
          next unless Users::SafeSettings.new(settings).public_send("#{kind}_digest_emails_enabled?")

          users[index][:id]
        end
        expect(jobs.map { |job| job['arguments'].first }).to eq(expected_ids)
        expect(jobs.length).to be > 1000 if id == 'two_batches'
        expect(jobs.map { |job| job['timezone'] }.uniq).to eq([Time.zone.name])
        {
          'id' => "#{id}_#{kind}", 'kind' => kind, 'now' => instant, 'ambient_zone' => zone,
          'period' => { 'year' => target.year, 'month' => kind == 'monthly' ? target.month : nil },
          'users' => users.as_json, 'stats' => stats.as_json, 'jobs' => jobs
        }
      end
    end
  end

  def digest_job_worker(kind, profile, locale)
    source_profile = %w[missing_user deleted_user no_data existing].include?(profile) ? profile : 'berlin'
    digest_users(source_profile)
    settings = { 'timezone' => 'Asia/Tokyo', 'locale' => " #{locale.upcase} " }
    User.unscoped.where(id: digest_user_id).update_all(settings:)
    digest_stats(source_profile, 2025, 3)
    digest_points(source_profile, 2025, 3) unless source_profile == 'no_data'
    if profile == 'year_boundary'
      Point.insert_all!([Time.utc(2024, 12, 31, 16, 30), Time.utc(2025, 12, 31, 20)].each_with_index.map do |at, index|
        { id: 14_290 + index, user_id: digest_user_id, timestamp: at.to_i, lonlat: 'POINT(12 51)',
          country_name: index.zero? ? 'Outside ambient year' : 'Inside ambient year', velocity: '0', anomaly: false,
          created_at: digest_now, updated_at: digest_now }
      end)
    end
    digest_tracks(source_profile, 2025, 3, nil)
    digest_existing(source_profile, kind, 2025, 3)
    ActiveRecord::Base.connection.execute("SELECT setval('digests_id_seq', 140500, false)")
    ActiveRecord::Base.connection.execute("SELECT setval('stats_id_seq', 150500, false)")
    uuid_index = 141_000
    allow(SecureRandom).to receive(:uuid) do
      uuid_index += 1
      format('00000000-0000-4000-8000-%012d', uuid_index)
    end
    calls = []
    error_class = profile.include?('database') ? ActiveRecord::StatementInvalid : StandardError
    error = error_class.new('synthetic digest failure')
    error.set_backtrace((1..25).map { |line| "synthetic frame #{line}" })
    allow(Stats::CalculateMonth).to receive(:new).and_wrap_original do |original, *args|
      calls << { 'kind' => 'stats', 'month' => args[2], 'locale' => I18n.locale.to_s, 'zone' => Time.zone.name }
      raise error if profile == 'stats_raise' || (profile == 'late_stats_raise' && args[2] == 7)

      original.call(*args)
    end
    calculator = kind == 'monthly' ? Users::Digests::CalculateMonth : Users::Digests::CalculateYear
    allow(calculator).to receive(:new).and_wrap_original do |original, *args|
      calls << { 'kind' => 'digest', 'locale' => I18n.locale.to_s, 'zone' => Time.zone.name }
      raise error if %w[digest_raise digest_database].include?(profile)

      original.call(*args)
    end
    if %w[stats_return stats_database].include?(profile)
      allow_any_instance_of(Stats::CalculateMonth).to receive(:points).and_raise(error)
    end
    if profile == 'vanished'
      allow(Stats::CalculateMonth).to receive(:new) do
        User.unscoped.where(id: digest_user_id).update_all(deleted_at: digest_now)
        raise error
      end
    end
    input = digest_input
    before = digest_rows
    clear_enqueued_jobs
    job = digest_job_class(kind, 'CalculatingJob').new
    job.job_id = '00000000-0000-4000-8000-000000141001'
    args = [digest_user_id, 2025]
    args << 3 if kind == 'monthly'
    job.perform(*args)
    emails = digest_job_enqueued
    notifications = Notification.where(user_id: digest_user_id).order(:id).pluck(:kind, :title, :content)
    terminal_profiles = %w[stats_raise digest_raise digest_database late_stats_raise vanished missing_user deleted_user]
    terminal = terminal_profiles.include?(profile)
    expect(emails.length).to eq(terminal ? 0 : 1)
    unless terminal
      expect(emails.first['job_class']).to eq(digest_job_class(kind, 'EmailSendingJob').name)
      expect(emails.first['arguments']).to eq(args)
      expect(emails.first.values_at('locale', 'timezone')).to eq([locale, 'Europe/Berlin'])
      expect(calls.select { |call| call['kind'] == 'stats' }.map { |call| call['month'] })
        .to eq(kind == 'monthly' ? [3] : (1..12).to_a)
    end
    if %w[stats_raise digest_raise digest_database late_stats_raise].include?(profile)
      expect(notifications.length).to eq(1)
      expect(notifications.first.last).to include('synthetic frame 20')
      expect(notifications.first.last).not_to include('synthetic frame 21')
    end
    expect(notifications).to be_empty if %w[vanished missing_user deleted_user].include?(profile)
    expect(notifications).to be_empty if %w[new existing no_data].include?(profile)
    expect(digest_rows).to be_empty if profile == 'no_data'
    if profile == 'late_stats_raise'
      expect(Stat.where(user_id: digest_user_id, year: 2025, month: 3).pick(:calculation_version)).to eq(3)
    end
    {
      'id' => "#{profile}_#{kind}_#{locale}", 'kind' => kind, 'profile' => profile, 'locale' => locale,
      'args' => args, 'ambient_zone' => Time.zone.name, 'input' => input, 'before' => before,
      'expected' => { 'rows' => digest_rows, 'calls' => calls, 'emails' => emails, 'notifications' => notifications,
                      'stats' => digest_select('SELECT user_id, year, month, distance, flight_distance, ' \
                                               'daily_distance, toponyms, h3_hex_ids, calculation_version FROM stats ' \
                                               "WHERE user_id = #{digest_user_id} ORDER BY year, month") }
    }
  end

  def digest_job_class(kind, suffix)
    "Users::Digests::#{kind.capitalize}::#{suffix}".constantize
  end

  def digest_job_enqueued
    enqueued_jobs.map do |job|
      job.slice('job_class', 'job_id', 'arguments', 'timezone', 'locale', 'queue_name')
    end
  end

  def digest_job_triggers
    original = ENV['TZ']
    schedule = YAML.load_file(Rails.root.join('config/schedule.yml'))
    cases = [
      ['winter', nil, 'Europe/Berlin', '2025-01-01T00:00:00Z'],
      ['summer', nil, 'Europe/Berlin', '2025-07-01T00:00:00Z'],
      ['override', 'Asia/Tokyo', 'Europe/Berlin', '2025-01-01T00:00:00Z'],
      ['southern_summer', 'Australia/Sydney', 'Europe/Berlin', '2025-01-01T00:00:00Z'],
      ['southern_winter', 'Australia/Sydney', 'Europe/Berlin', '2025-07-01T00:00:00Z'],
      ['os', nil, nil, '2025-01-01T00:00:00Z']
    ]
    cases.flat_map do |id, tz, zone, instant|
      tz ? ENV['TZ'] = tz : ENV.delete('TZ')
      Time.use_zone(zone) do
        %w[monthly yearly].map do |kind|
          entry = schedule.fetch("#{kind}_digest_scheduling_job")
          cron = Sidekiq::Cron::Job.allocate.send(:do_parse_cron, entry.fetch('cron'))
          resolved = EtOrbi.determine_local_tzone.name
          at = cron.next_time(Time.iso8601(instant)).to_t.utc.iso8601
          expect(at).to eq('2025-01-02T03:00:00Z') if id == 'winter' && kind == 'monthly'
          expect(at).to eq('2025-07-02T02:00:00Z') if id == 'summer' && kind == 'monthly'
          expect(at).to eq('2025-01-02T05:00:00Z') if id == 'winter' && kind == 'yearly'
          { 'id' => "#{id}_#{kind}", 'kind' => kind, 'cron' => entry.fetch('cron'), 'tz' => tz,
            'rails_zone' => zone, 'resolved_zone' => resolved, 'after' => instant, 'fires_at' => at }
        end
      end
    end
  ensure
    original ? ENV['TZ'] = original : ENV.delete('TZ')
  end

  context 'A12d1b3 committed source captures' do
    self.use_transactional_tests = false

    before { phoenix_tables! }

    it 'writes or matches the A12d1b3 recalculation corpus twice byte-identically' do
      first = recalculation_capture
      expect(recalculation_capture).to eq(first)
      expect(first).not_to include(Rails.root.to_s)
      destination = Rails.root.join('app-phoenix/test/fixtures/a12d1b3/recalculations.json')
      if ENV['WRITE_PHOENIX_FIXTURES'] == '1'
        FileUtils.mkdir_p(destination.dirname)
        File.write(destination, first)
      else
        expect(first).to eq(destination.read)
      end
    end

    def recalculation_capture
      cases = recalculation_profiles.map do |profile|
        RSpec::Mocks.with_temporary_scope do
          recalculation_isolated { recalculation_case(profile) }
        end
      end
      digest_json('version' => 1, 'cases' => cases, 'timestamps' => recalculation_timestamps,
                  'policies' => recalculation_policies, 'release_zones' => recalculation_release_zones,
                  'mixed_retries' => recalculation_mixed_retries)
    end

    def recalculation_mixed_retries
      RSpec::Mocks.with_temporary_scope do
        recalculation_isolated do
          source = recalculation_case('fleet_rebuild_retry')
          steps = [recalculation_retry_snapshot('first_error')]
          job = DataMigrations::RecalculateAnomaliesUserJob.deserialize(enqueued_jobs.last)
          clear_enqueued_jobs
          expect(PhoenixLease.acquire('anomaly_backfill:170101', 'synthetic-busy', 60)).to be(true)
          job.perform_now
          steps << recalculation_retry_snapshot('busy')
          expect(enqueued_jobs.last.fetch('exception_executions')).to eq({})
          PhoenixLease.release('anomaly_backfill:170101', 'synthetic-busy')
          3.times do |index|
            job = DataMigrations::RecalculateAnomaliesUserJob.deserialize(enqueued_jobs.last)
            clear_enqueued_jobs
            job.perform_now
            steps << recalculation_retry_snapshot("after_busy_error_#{index + 1}")
          end
          expect(steps.map { |step| step.fetch('failed') }).to eq([false, false, false, false, true])
          expect(steps.map { |step| step.fetch('slots') }).to eq([0, 0, 0, 0, 1])
          { 'input' => source.fetch('input'), 'steps' => steps }
        end
      end
    end

    def recalculation_retry_snapshot(name)
      jobs = recalculation_jobs
      retry_job = jobs.find { |job| job['job_class'] == 'DataMigrations::RecalculateAnomaliesUserJob' }
      failed = DataMigrations::RecalculateAnomaliesUserJob::FAILED_SETTINGS_KEY
      { 'name' => name, 'jobs' => jobs, 'failed' => User.find(170_101).settings.key?(failed),
        'slots' => jobs.count { |job| job['job_class'] == 'DataMigrations::RecalculateAnomaliesJob' },
        'delay' => retry_job && Time.iso8601(retry_job.fetch('scheduled_at')).to_i - digest_now.to_i }
    end

    def recalculation_release_zones
      %w[Europe/Berlin Asia/Tokyo].map do |zone|
        fleet = RSpec::Mocks.with_temporary_scope do
          recalculation_isolated { Time.use_zone(zone) { recalculation_case('fleet_disabled') } }
        end
        tracker = RSpec::Mocks.with_temporary_scope do
          recalculation_isolated { Time.use_zone(zone) { recalculation_boundary_tracker } }
        end
        { 'zone' => zone, 'fleet' => fleet, 'tracker' => tracker }
      end
    end

    def recalculation_boundary_tracker
      User.unscoped.insert_all!([{ id: 170_101, email: 'boundary@example.invalid', encrypted_password: '',
                                  status: 1, plan: 1, settings: { 'gps_filtering_enabled' => false },
                                  created_at: digest_now, updated_at: digest_now }])
      Import.insert_all!([{ id: 170_801, user_id: 170_101, name: 'Records.json',
                           source: Import.sources[:google_records], created_at: digest_now, updated_at: digest_now }])
      at = Timestamps.parse_timestamp('1960-01-01T00:00:00Z')
      Point.insert_all!([{ id: 170_201, user_id: 170_101, import_id: 170_801, timestamp: at,
                          lonlat: 'POINT(12 51)', tracker_id: 'legacy-import-170801', raw_data: {},
                          created_at: digest_now, updated_at: digest_now }])
      records = Oj.dump({ 'locations' => [{ 'timestamp' => '1960-01-01T00:00:00Z', 'deviceTag' => 77,
                                          'latitudeE7' => 510_000_000, 'longitudeE7' => 120_000_000 }] }, mode: :strict)
      import = Import.find(170_801)
      import.file.attach(io: StringIO.new(records), filename: 'Records.json', content_type: 'application/json')
      @recalculation_blob_ids << import.file.blob.id
      input = recalculation_rows(input: true)
      count = Points::DeviceTagBackfiller.new(import).call
      expect(count).to eq(1)
      expect(Point.find(170_201).tracker_id).to eq('google-records-device-77')
      { 'input' => input, 'records' => records, 'timestamp' => at, 'count' => count,
        'tracker_id' => Point.find(170_201).tracker_id }
    end

    def recalculation_profiles
      %w[full full_missing full_deleted full_stale
         user_all user_specific user_coerced user_zero user_blank user_float user_invalid_year
         user_tokyo user_dst user_invalid_zone user_nested_argument user_no_data user_missing user_deleted
         user_notify_false user_notify_null user_notify_empty user_stats_handled user_stats_escape
         user_digest_escape user_busy user_busy_exhausted user_busy_false user_busy_null user_busy_empty
         backfill_reset backfill_async backfill_nonreset backfill_disabled backfill_busy backfill_interrupted
         fleet_success fleet_missing fleet_done fleet_disabled fleet_busy fleet_busy_exhausted fleet_interrupted
         fleet_rebuild_retry fleet_rebuild_exhausted fleet_manual_failed fleet_done_empty
         dispatch_predicates dispatch_disabled dispatch_malformed tracker_records tracker_missing tracker_corrupt
         tracker_retry tracker_stagger tracker_stagger_zero]
    end

    def recalculation_isolated(&block)
      connection = ActiveRecord::Base.connection
      configuration = ActiveRecord::Base.connection_db_config.configuration_hash
      fixture_mode = use_transactional_tests
      expect(connection.open_transactions).to eq(0)
      @recalculation_sessions = []
      @recalculation_blob_ids = []
      sequences = %w[stats_id_seq digests_id_seq notifications_id_seq active_storage_blobs_id_seq
                     active_storage_attachments_id_seq active_storage_variant_records_id_seq
                     phoenix.achievement_check_revisions].index_with do |sequence|
        connection.select_one("SELECT last_value, is_called FROM #{sequence}")
      end
      sequences.each_key { |sequence| connection.execute("SELECT setval('#{sequence}', 170900, false)") }
      uuid_index = 170_000
      allow(SecureRandom).to receive(:uuid) do
        uuid_index += 1
        format('00000000-0000-4000-8000-%012d', uuid_index)
      end
      allow(SecureRandom).to receive(:hex).with(8).and_return('1700000000000000')
      allow(Kernel).to receive(:rand).and_call_original
      allow(Kernel).to receive(:rand).with(no_args).and_return(0)
      allow(ActiveStorage::Blob).to receive(:generate_unique_secure_token).and_return('a12d1b3-records-source')
      allow(Tracks::SessionManager).to receive(:create_for_user).and_wrap_original do |original, *args|
        original.call(*args).tap { |session| @recalculation_sessions << session }
      end
      travel_to(digest_now) { Time.use_zone('Europe/Berlin', &block) }
    ensure
      begin
        @recalculation_sessions&.each(&:cleanup_session)
        ActiveStorage::Attachment.where(blob_id: @recalculation_blob_ids || []).delete_all
        ActiveStorage::Blob.where(id: @recalculation_blob_ids || []).find_each(&:purge)
        TrackSegment.where(track_id: Track.where(user_id: 170_101..170_120).select(:id)).delete_all
        [Point, Track, Stat, Users::Digest, Notification, Import].each do |model|
          model.where(user_id: 170_101..170_120).delete_all
        end
        User.unscoped.where(id: 170_101..170_120).delete_all
        %w[stats_full_recalculation:user:170101 anomaly_backfill:170101 tracks:per_user_lock:170101].each do |key|
          connection.execute("DELETE FROM phoenix.once_claims WHERE key = #{connection.quote(key)}")
          connection.execute("DELETE FROM phoenix.leases WHERE name = #{connection.quote(key)}")
        end
        connection.execute('DELETE FROM phoenix.achievement_checks WHERE user_id = 170101')
        Rails.cache.delete('dawarich/user_170101_years_tracked')
        %w[points tracks].each do |domain|
          %w[all 2024 2025].each { |year| Rails.cache.delete("#{domain}:tile_epoch:170101:#{year}") }
        end
      ensure
        sequences&.each do |sequence, state|
          connection.execute("SELECT setval('#{sequence}', #{state.fetch('last_value')}, " \
                             "#{connection.quote(state.fetch('is_called'))})")
        end
        clear_enqueued_jobs
        ActiveRecord::Base.connection_pool.release_connection
        ActiveRecord::Base.establish_connection(configuration) if configuration
        self.use_transactional_tests = fixture_mode unless fixture_mode.nil?
      end
    end

    def recalculation_case(profile)
      settings = { 'timezone' => 'Europe/Berlin', 'locale' => ' FR ', 'gps_filtering_enabled' => true }
      settings['timezone'] = 'Asia/Tokyo' if profile == 'user_tokyo'
      settings['timezone'] = 'Unknown/Zone' if profile == 'user_invalid_zone'
      settings['gps_filtering_enabled'] = 'off' if profile.end_with?('_disabled')
      done = DataMigrations::RecalculateAnomaliesUserJob::RECALCULATED_SETTINGS_KEY
      failed = DataMigrations::RecalculateAnomaliesUserJob::FAILED_SETTINGS_KEY
      settings[done] = digest_now.iso8601 if profile == 'fleet_done'
      settings[done] = '' if profile == 'fleet_done_empty'
      settings[failed] = digest_now.iso8601 if profile == 'fleet_manual_failed'
      missing = %w[full_missing user_missing fleet_missing].include?(profile)
      unless missing
        User.unscoped.insert_all!([{ id: 170_101, email: 'a12d1b3@example.invalid', encrypted_password: '',
                                    status: 1, plan: 1, settings:,
                                    deleted_at: profile.end_with?('_deleted') ? digest_now : nil,
                                    created_at: digest_now, updated_at: digest_now }])
      end
      recalculation_points unless missing || profile == 'user_no_data'
      calls = recalculation_observe(profile)
      case profile
      when /^full/ then recalculation_full(profile, calls)
      when /^user/ then recalculation_user(profile, calls)
      when /^backfill/ then recalculation_backfill(profile, calls)
      when /^fleet/ then recalculation_fleet(profile, calls)
      when /^dispatch/ then recalculation_dispatch(profile, calls)
      when /^tracker/ then recalculation_tracker(profile, calls)
      end
    end

    def recalculation_points
      instants = ['2024-12-31T23:30:00Z', '2025-01-01T01:00:00Z', '2025-03-15T12:00:00Z',
                  '2025-03-15T12:00:00Z', '2025-03-15T12:00:00Z', '2025-03-15T12:10:00Z',
                  '2025-03-30T00:30:00Z', '2025-12-31T23:30:00Z']
      Point.insert_all!(instants.each_with_index.map do |instant, index|
        position = (2..4).cover?(index) ? index - 2 : index
        { id: 170_201 + index, user_id: 170_101, timestamp: Time.iso8601(instant).to_i,
          lonlat: "POINT(#{12 + position * 0.0001} #{51 + position * 0.0001})", velocity: '0',
          anomaly: index.zero?, tracker_id: index == 7 ? 'real-device' : nil,
          raw_data: index == 1 ? { 'deviceTag' => ' 7 ', 'tid' => 'ignored' } : { 'tid' => ' real-tid ' },
          created_at: digest_now, updated_at: digest_now }
      end)
    end

    def recalculation_observe(profile)
      calls = []
      error = StandardError.new('synthetic recalculation failure')
      error.set_backtrace((1..25).map { |line| "synthetic frame #{line}" })
      replayed = false
      allow(Stats::CalculateMonth).to receive(:new).and_wrap_original do |original, *args|
        calls << { 'kind' => 'stats', 'args' => args, 'locale' => I18n.locale.to_s, 'zone' => Time.zone.name }
        raise error if profile == 'user_stats_escape'

        if profile == 'user_nested_argument' && args.last == 2 && !replayed
          replayed = true
          raise ArgumentError, 'synthetic nested argument'
        end
        original.call(*args)
      end
      if profile == 'user_stats_handled'
        allow_any_instance_of(Stats::CalculateMonth).to receive(:points).and_raise(error)
      end
      allow(Tracks::ParallelGenerator).to receive(:new).and_wrap_original do |original, user, **kwargs|
        calls << { 'kind' => 'tracks', 'user_id' => user.id, 'options' => kwargs.as_json,
                   'locale' => I18n.locale.to_s, 'zone' => Time.zone.name,
                   'start_timestamp' => kwargs.fetch(:start_at).to_i,
                   'end_timestamp' => kwargs.fetch(:end_at).to_i,
                   'end_microsecond' => kwargs.fetch(:end_at).usec }
        if profile.include?('busy') && profile.start_with?('user_')
          raise Tracks::PerUserLock::AcquisitionTimeout, 'synthetic track lock contention'
        end
        raise error if profile.start_with?('fleet_rebuild')

        recalculation_service(original.call(user, **kwargs), calls.last)
      end
      allow(Users::Digests::CalculateYear).to receive(:new).and_wrap_original do |original, *args|
        calls << { 'kind' => 'digest', 'args' => args, 'locale' => I18n.locale.to_s, 'zone' => Time.zone.name }
        raise error if profile == 'user_digest_escape'

        recalculation_service(original.call(*args), calls.last)
      end
      allow(Points::AnomalyFilter).to receive(:new).and_wrap_original do |original, *args, **kwargs|
        calls << { 'kind' => 'filter', 'args' => args, 'options' => kwargs.as_json }
        original.call(*args, **kwargs)
      end
      allow(Points::TileEpoch).to receive(:bump).and_wrap_original do |original, *args, **kwargs|
        calls << { 'kind' => 'points.tile_epoch', 'args' => args, 'options' => kwargs.as_json }
        original.call(*args, **kwargs)
      end
      calls
    end

    def recalculation_service(service, row)
      allow(service).to receive(:call).and_wrap_original do |original|
        result = original.call
        row['result'] = result.is_a?(Tracks::SessionManager) ? result.get_session_data : result.as_json
        result
      end
      service
    end

    def recalculation_full(profile, calls)
      key = 'stats_full_recalculation:user:170101'
      PhoenixClaims.debounce(key, 300)
      if profile == 'full_stale'
        user = User.find(170_101)
        user.years_tracked
        Point.insert_all!([{ id: 170_220, user_id: user.id, timestamp: Time.utc(2025, 6, 1, 12).to_i,
                            lonlat: 'POINT(13 52)', anomaly: true, created_at: digest_now, updated_at: digest_now }])
      end
      job = Stats::FullRecalculationJob.new(170_101)
      recalculation_run(profile, job, calls) do
        result = job.perform_now
        expect(claim_seconds(key)).to be_nil
        jobs = recalculation_jobs
        if %w[full_missing full_deleted].include?(profile)
          expect(jobs).to be_empty
        else
          expect(jobs).not_to be_empty
          expect(jobs.map { |row| row['job_class'] }.uniq).to eq(['Stats::CalculatingJob'])
          expect(jobs.map { |row| row['arguments'][1] }).to eq(jobs.map { |row| row['arguments'][1] }.sort.reverse)
        end
        result
      end
    end

    def recalculation_user(profile, calls)
      year = case profile
             when 'user_all', 'user_no_data', 'user_missing', 'user_deleted' then nil
             when 'user_coerced' then ' 2025tail'
             when 'user_zero' then 0
             when 'user_blank' then ''
             when 'user_float' then 2025.9
             when 'user_invalid_year' then true
             else 2025
             end
      notify = case profile
               when 'user_notify_false', 'user_busy_false' then false
               when 'user_notify_null', 'user_busy_null' then nil
               when 'user_notify_empty', 'user_busy_empty' then ''
               else true
               end
      job = Users::RecalculateDataJob.new(170_101, year:, notify:)
      job.exception_executions = { '[Tracks::PerUserLock::AcquisitionTimeout]' => 4 } if profile.include?('busy_')
      recalculation_run(profile, job, calls) do
        result = job.perform_now
        unless %w[user_missing user_deleted user_no_data].include?(profile) || profile.include?('busy')
          kinds = calls.map { |row| row['kind'] }.select { |kind| %w[stats tracks digest].include?(kind) }
          expect(kinds).to eq(kinds.sort_by { |kind| %w[stats tracks digest].index(kind) })
          expect(calls.select { |row| row['kind'] == 'tracks' }).not_to be_empty
          track_calls = calls.select { |row| row['kind'] == 'tracks' }
          expect(track_calls.map { |row| row['end_microsecond'] }.uniq).to eq([999_999])
          expect(recalculation_jobs.none? { |row| row['job_class'].include?('EmailSending') }).to be(true)
        end
        result
      end
    end

    def recalculation_backfill(profile, calls)
      reset = profile != 'backfill_nonreset'
      rebuild = profile == 'backfill_async' ? :async : :inline
      job = Points::AnomalyBackfillUserJob.new(170_101, reset:, notify: true, rebuild:)
      if profile == 'backfill_busy'
        expect(PhoenixLease.acquire('anomaly_backfill:170101', 'synthetic-busy', 60)).to be(true)
      end
      recalculation_run(profile, job, calls) do
        result = if profile == 'backfill_interrupted'
                   interrupt_job_during_step(Points::AnomalyBackfillUserJob, :filter_months,
                                             cursor: Time.utc(2025, 1, 1).to_i) { job.perform_now }
                 else
                   job.perform_now
                 end
        expect(result).to be(profile != 'backfill_busy') unless profile == 'backfill_interrupted'
        if profile == 'backfill_busy'
          expect(enqueued_jobs).to be_empty
          expect(Point.find(170_201).anomaly).to be(true)
          expect(Notification.where(user_id: 170_101)).not_to exist
          PhoenixLease.release('anomaly_backfill:170101', 'synthetic-busy')
          expect(enqueued_jobs).to be_empty
          expect(calls).to be_empty
        end
        if %w[backfill_reset backfill_disabled].include?(profile)
          expect(Point.find(170_201).anomaly).to be(false)
          expect(calls.any? { |row| row['kind'] == 'points.tile_epoch' }).to be(true)
          expect(calls.any? { |row| row['kind'] == 'tracks' }).to be(true)
        end
        result
      end
    end

    def recalculation_fleet(profile, calls)
      if profile.include?('busy')
        expect(PhoenixLease.acquire('anomaly_backfill:170101', 'synthetic-busy', 60)).to be(true)
      end
      attempt = profile == 'fleet_busy_exhausted' ? 8 : 1
      job = DataMigrations::RecalculateAnomaliesUserJob.new(170_101, attempt:)
      job.exception_executions = { '[StandardError]' => 2 } if profile == 'fleet_rebuild_exhausted'
      recalculation_run(profile, job, calls) do
        result = if profile == 'fleet_interrupted'
                   interrupt_job_during_step(Points::AnomalyBackfillUserJob, :filter_months,
                                             cursor: Time.utc(2025, 1, 1).to_i) { job.perform_now }
                 else
                   job.perform_now
                 end
        successors = recalculation_jobs.select { |row| row['job_class'] == 'DataMigrations::RecalculateAnomaliesJob' }
        terminal = !%w[fleet_busy fleet_rebuild_retry].include?(profile)
        expect(successors.size).to eq(terminal ? 1 : 0)
        expect(successors.first['arguments']).to eq([{ 'limit' => 1, '_aj_ruby2_keywords' => ['limit'] }]) if terminal
        if %w[fleet_success fleet_manual_failed fleet_done_empty].include?(profile)
          done = DataMigrations::RecalculateAnomaliesUserJob::RECALCULATED_SETTINGS_KEY
          expect(User.find(170_101).settings[done]).to be_present
          expect(calls.any? { |row| row['kind'] == 'tracks' }).to be(true)
          expect(Notification.where(user_id: 170_101).count).to eq(1)
        end
        result
      end
    end

    def recalculation_dispatch(profile, calls)
      User.unscoped.where(id: 170_101).delete_all if Point.where(user_id: 170_101).delete_all >= 0
      queued = DataMigrations::RecalculateAnomaliesUserJob::QUEUED_SETTINGS_KEY
      done = DataMigrations::RecalculateAnomaliesUserJob::RECALCULATED_SETTINGS_KEY
      failed = DataMigrations::RecalculateAnomaliesUserJob::FAILED_SETTINGS_KEY
      stamps = [{}, { queued => nil }, { queued => 'garbage' }, { queued => '2020-01-01T10:00:00-07:00' },
                { queued => '2026-10-03T05:00:00-07:00' }, { queued => 'garbage', done => nil },
                { failed => nil }, { failed => false }, { 'gps_filtering_enabled' => 'off' },
                { 'gps_filtering_enabled' => '' }]
      stamps = [{ queued => '2025-99-99T01:02:03Z' }] if profile == 'dispatch_malformed'
      if profile == 'dispatch_disabled'
        stamps = ['off', '0', false, '', nil, true].map { |value| { 'gps_filtering_enabled' => value } }
      end
      stamps.each_with_index do |stamp, index|
        id = 170_101 + index
        User.unscoped.insert_all!([{ id:, email: "a12d1b3-dispatch-#{index}@example.invalid", encrypted_password: '',
                                    points_count: 0, status: 1, plan: 1, settings: stamp,
                                    created_at: digest_now, updated_at: digest_now }])
        Point.insert_all!([{ id: 170_201 + index, user_id: id, timestamp: Time.utc(2025, 3, 15).to_i,
                            lonlat: 'POINT(12 51)', anomaly: true, created_at: digest_now, updated_at: digest_now }])
      end
      job = DataMigrations::RecalculateAnomaliesJob.new
      recalculation_run(profile, job, calls) do
        runnable = job.send(:pending_users).order(:id).pluck(:id)
        calls << { 'kind' => 'pending', 'user_ids' => runnable }
        expect(runnable).not_to include(170_105, 170_106, 170_107, 170_108) if profile == 'dispatch_predicates'
        result = job.perform_now
        expect(recalculation_jobs.size).to eq(2)
        if profile == 'dispatch_disabled'
          expect(User.where(id: 170_101..170_104).pluck(:settings).all? { |settings| settings.key?(done) }).to be(true)
          expect(Point.where(user_id: 170_101..170_104).pluck(:anomaly).uniq).to eq([true])
        end
        result
      end
    end

    def recalculation_tracker(profile, calls)
      Import.insert_all!([{ id: 170_801, user_id: 170_101, name: 'Records.json',
                           source: Import.sources[:google_records],
                           created_at: digest_now, updated_at: digest_now }])
      Point.where(id: 170_203..170_206).update_all(import_id: 170_801, tracker_id: 'legacy-import-170801')
      if %w[tracker_records tracker_retry tracker_corrupt].include?(profile)
        bytes = Rails.root.join('app-phoenix/test/fixtures/a12d1b3/Records.json').binread
        bytes = '{broken' if profile == 'tracker_corrupt'
        import = Import.find(170_801)
        import.file.attach(io: StringIO.new(bytes), filename: 'Records.json', content_type: 'application/json')
        @recalculation_blob_ids << import.file.blob.id
      end
      allow(Points::DeviceTagBackfiller).to receive(:new).and_wrap_original do |original, *args|
        calls << { 'kind' => 'records', 'import_id' => args.first.id }
        recalculation_service(original.call(*args), calls.last)
      end
      allow(Points::TrackerIdBackfiller).to receive(:new).and_wrap_original do |original, *args|
        calls << { 'kind' => 'raw', 'user_id' => args.first.id }
        recalculation_service(original.call(*args), calls.last)
      end
      once = false
      if profile == 'tracker_retry'
        allow(Users::RecalculateDataJob).to receive(:new).and_wrap_original do |original, *args|
          unless once
            once = true
            raise Tracks::PerUserLock::AcquisitionTimeout, 'synthetic rebuild contention'
          end
          original.call(*args)
        end
      end
      stagger = profile.start_with?('tracker_stagger')
      job = if stagger
              DataMigrations::RecalculatePerTrackerTracksJob.new
            else
              DataMigrations::RecalculatePerTrackerTracksJob.new(170_101)
            end
      delay = profile == 'tracker_stagger_zero' ? 0 : 3600
      allow(job).to receive(:rand).with(0..3600).and_return(delay) if stagger
      recalculation_run(profile, job, calls) do
        if profile == 'tracker_retry'
          expect do
            job.perform_now
          end.to raise_error(Tracks::PerUserLock::AcquisitionTimeout, 'synthetic rebuild contention')
          expect(Point.where(user_id: 170_101, tracker_id: nil)).not_to exist
        end
        result = job.perform_now
        if stagger
          expect(recalculation_jobs.size).to eq(1)
          expect(recalculation_jobs.first['arguments']).to eq([170_101])
          expect(Time.iso8601(recalculation_jobs.first.fetch('scheduled_at')).to_i).to eq(digest_now.to_i + delay)
        else
          expect(calls.index { |row| row['kind'] == 'records' }).to be < calls.index { |row| row['kind'] == 'raw' }
          expect(calls.any? { |row| row['kind'] == 'tracks' }).to be(true)
          expect(Point.find(170_208).tracker_id).to eq('real-device')
          expect(Point.find(170_202).tracker_id).to eq('google-records-device-7')
          expect(Notification.where(user_id: 170_101)).not_to exist
          if %w[tracker_records tracker_retry].include?(profile)
            expect(Point.where(id: 170_203..170_206).order(:id).pluck(:tracker_id))
              .to eq(%w[google-records-device-11 google-records-device-22
                        legacy-import-170801 google-records-device-55])
          end
        end
        result
      end
    end

    def recalculation_run(profile, job, calls)
      clear_enqueued_jobs
      job.job_id = '00000000-0000-4000-8000-000000170001'
      input = recalculation_rows(input: true)
      serialization = job.serialize.deep_dup
      result = error = nil
      begin
        result = yield
      rescue StandardError => e
        raise if e.is_a?(RSpec::Expectations::ExpectationNotMetError)

        error = { 'class' => e.class.name, 'message' => e.message }
      end
      faults = %w[user_stats_escape user_digest_escape user_invalid_year dispatch_malformed]
      expect(error).to be_nil unless faults.include?(profile)
      expect(error).not_to be_nil if faults.include?(profile)
      parents = calls.select { |row| row['kind'] == 'tracks' && row['result'].is_a?(Hash) }
      parents.each do |row|
        expect(row['result'].fetch('status')).to eq('processing')
        expect(row['result'].fetch('total_chunks')).to be_positive
        expect(row['result'].fetch('completed_chunks')).to eq(0)
      end
      if %w[user_all user_specific backfill_reset backfill_disabled fleet_success tracker_records tracker_retry]
         .include?(profile)
        expect(parents).not_to be_empty
      end
      notifications = Notification.where(user_id: 170_101).order(:id).pluck(:kind, :title, :content)
      if %w[user_stats_escape user_digest_escape].include?(profile)
        expect(notifications.first.last).to include('synthetic frame 10')
        expect(notifications.first.last).not_to include('synthetic frame 11')
      end
      result = result.serialize if result.is_a?(ActiveJob::Base)
      { 'id' => profile, 'job' => serialization, 'input' => input, 'ambient_zone' => Time.zone.name,
        'database_zone' => ActiveRecord::Base.connection.select_value('SHOW timezone'),
        'expected' => { 'result' => result.as_json, 'error' => error, 'rows' => recalculation_rows,
                        'calls' => calls, 'jobs' => recalculation_jobs,
                        'notifications' => notifications } }
    end

    def recalculation_rows(input: false)
      user_ids = (170_101..170_120).to_a.join(',')
      tables = %w[users imports points stats tracks track_segments digests].index_with do |table|
        filter = table == 'users' ? "id IN (#{user_ids})" : "user_id IN (#{user_ids})"
        filter = "track_id IN (SELECT id FROM tracks WHERE user_id IN (#{user_ids}))" if table == 'track_segments'
        projection = case table
                     when 'users' then 'id, email, encrypted_password, settings, status, plan, deleted_at, ' \
                                       'created_at, updated_at'
                     when 'points' then 'id, user_id, import_id, timestamp, ST_AsText(lonlat) AS lonlat, tracker_id, ' \
                                        'track_id, anomaly, raw_data, velocity, created_at, ' \
                                        "CASE WHEN updated_at = created_at THEN 'unchanged' " \
                                        "ELSE 'updated' END AS update_state"
                     else '*'
                     end
        if input && table == 'points'
          projection = projection.sub("CASE WHEN updated_at = created_at THEN 'unchanged' " \
                                      "ELSE 'updated' END AS update_state", 'updated_at')
        end
        digest_select("SELECT #{projection} FROM #{table} WHERE #{filter} ORDER BY id")
      end
      tables.merge('active_storage_blobs' => digest_select('SELECT * FROM active_storage_blobs WHERE id = 170900'),
                   'active_storage_attachments' => digest_select('SELECT * FROM active_storage_attachments ' \
                     "WHERE record_type = 'Import' AND record_id = 170801"))
    end

    def recalculation_jobs
      enqueued_jobs.map do |job|
        job.slice('job_class', 'job_id', 'arguments', 'timezone', 'locale', 'queue_name',
                  'scheduled_at', 'executions', 'exception_executions', 'continuation', 'resumptions')
      end
    end

    def recalculation_timestamps
      values = [nil, 0, 1_742_040_000, 1_742_040_000_000, '1742040000000', '-1', '-1000000000000',
                'garbage', '', '2025-03-15', '2025-03-15T12:00:00Z', '2025-03-15T12:00:00+09:00',
                '1960-01-01T00:00:00Z', '2200-01-01T00:00:00Z', '2025', true, {}, []]
      travel_to(digest_now) do
        %w[Europe/Berlin Asia/Tokyo Etc/UTC].flat_map do |zone|
          Time.use_zone(zone) do
            values.map do |value|
              result = error = nil
              begin
                result = Timestamps.parse_timestamp(value)
              rescue StandardError => e
                error = { 'class' => e.class.name, 'message' => e.message }
              end
              { 'zone' => zone, 'value' => value, 'result' => result, 'error' => error }
            end
          end
        end
      end
    end

    def recalculation_policies
      require 'sidekiq/job_retry'
      { 'sidekiq_retry' => Sidekiq.default_job_options.fetch('retry'),
        'retry_jitter' => Users::RecalculateDataJob.retry_jitter, 'jitter_draw' => 0,
        'sidekiq_max_retries' => Sidekiq.default_configuration[:max_retries] || Sidekiq::JobRetry::DEFAULT_MAX_RETRY_ATTEMPTS,
        'lock_attempts' => DataMigrations::RecalculateAnomaliesUserJob::MAX_LOCK_ATTEMPTS,
        'rebuild_attempts' => DataMigrations::RecalculateAnomaliesUserJob::MAX_REBUILD_ATTEMPTS,
        'lock_wait' => DataMigrations::RecalculateAnomaliesUserJob::LOCK_RETRY_WAIT.to_i,
        'max_resumptions' => Points::AnomalyBackfillUserJob.max_resumptions,
        'resume_wait' => Points::AnomalyBackfillUserJob.resume_options.fetch(:wait).to_i }
    end
  end

  context 'A12d1b4 source cache contracts', type: :request do
    let(:now) { Time.utc(2026, 10, 3, 12) }

    def cache_capture
      { 'version' => 1, 'completed_years' => cache_years, 'staleness' => cache_staleness,
        'warming' => cache_isolated { cache_warming }, 'readers' => cache_readers,
        'missing_users' => cache_missing_users, 'failure_boundary' => cache_failures,
        'eligibility' => cache_eligibility, 'http_scoping' => cache_isolated { cache_http_scoping },
        'fragments' => cache_isolated { cache_fragments }, 'trigger' => cache_trigger }
    end

    def cache_isolated
      connection = ActiveRecord::Base.connection
      sequences = %w[users points visits tracks track_segments stats digests countries
                     notifications].index_with do |table|
        connection.select_one("SELECT last_value, is_called FROM #{table}_id_seq")
      end
      caching = InsightsController.perform_caching
      locale = I18n.locale
      cache = {}
      result = nil
      RSpec::Mocks.with_temporary_scope do
        allow(DawarichSettings).to receive(:self_hosted?).and_return(false)
        %i[write_entry delete_entry].each do |method|
          allow(Rails.cache).to receive(method).and_wrap_original do |original, key, *args, **kwargs|
            cache_remember(cache, key)
            original.call(key, *args, **kwargs)
          end
        end
        allow(Rails.cache).to receive(:delete_matched).and_wrap_original do |original, pattern, **kwargs|
          cache_redis { |redis| redis.scan_each(match: pattern).each { |key| cache_remember(cache, key) } }
          original.call(pattern, **kwargs)
        end
        uuid_index = 180_500
        allow(SecureRandom).to receive(:uuid) do
          uuid_index += 1
          format('00000000-0000-4000-8000-%012d', uuid_index)
        end
        ActiveRecord::Base.transaction(requires_new: true) do
          sequences.each_key { |table| connection.execute("SELECT setval('#{table}_id_seq', 180500, false)") }
          travel_to(now) { Time.use_zone('Europe/Berlin') { result = yield cache } }
          raise ActiveRecord::Rollback
        end
      ensure
        cache_restore(cache)
      end
      result
    ensure
      sequences&.each do |table, state|
        connection.execute("SELECT setval('#{table}_id_seq', #{state.fetch('last_value')}, " \
                           "#{connection.quote(state.fetch('is_called'))})")
      end
      InsightsController.perform_caching = caching
      I18n.locale = locale if locale
      clear_enqueued_jobs
    end

    def cache_redis(&block)
      Rails.cache.redis.then { |client| client.respond_to?(:with) ? client.with(&block) : block.call(client) }
    end

    def cache_remember(cache, key)
      return if cache.key?(key)

      cache_redis do |redis|
        ttl = redis.pttl(key)
        cache[key] =
          [redis.get(key), ttl.negative? ? ttl : Process.clock_gettime(Process::CLOCK_MONOTONIC) + ttl / 1000.0]
      end
    end

    def cache_restore(cache)
      cache_redis do |redis|
        cache.each do |key, (bytes, expiry)|
          clock = Process.clock_gettime(Process::CLOCK_MONOTONIC)
          remaining = expiry.negative? ? expiry : ((expiry - clock) * 1000).floor
          if bytes.nil? || remaining == -2 || remaining.zero? || (expiry.positive? && remaining.negative?)
            redis.del(key)
          elsif remaining == -1
            redis.set(key, bytes)
          else
            redis.set(key, bytes, px: remaining)
          end
        end
      end
    end

    def cache_user(id = 180_101, **attributes)
      User.unscoped.insert_all!([{ id:, email: "cache-#{id}@example.invalid", encrypted_password: '',
                                  status: 1, plan: 1, settings: { 'timezone' => 'Asia/Tokyo' },
                                  created_at: now, updated_at: now }.merge(attributes)])
      User.unscoped.find(id)
    end

    def cache_stat(user, year, month = 1, stamp = now)
      Stat.insert_all!([{ user_id: user.id, year:, month:, distance: 1000, daily_distance: { '1' => 1000 },
                          flight_distance: 0, toponyms: [], h3_hex_ids: {}, calculation_version: 0,
                          created_at: stamp, updated_at: stamp }])
    end

    def cache_digest(user, year, patterns = { 'activity_breakdown' => { 'walking' => 1, 'flying' => 2 } }, stamp = now)
      Users::Digest.create!(user:, year:, period_type: :yearly, distance: 777, travel_patterns: patterns,
                            updated_at: stamp, created_at: stamp)
    end

    def cache_key(user, digest)
      "insights/yearly_digest/#{user.id}/#{digest.year}/#{digest.updated_at.to_i}"
    end

    def cache_years
      [['2026-10-03T12:00:00Z', 'Europe/Berlin'], ['2025-12-31T23:30:00Z', 'Europe/Berlin'],
       ['2025-12-31T23:30:00Z', 'Etc/UTC']].map do |instant, zone|
        cache_isolated do
          user = cache_user
          [2026, 2025, 2023, 2022].each { |year| cache_stat(user, year) }
          cache_stat(user, 2025, 2)
          travel_to(Time.iso8601(instant))
          Time.use_zone(zone) do
            years = Cache::PreheatInsightsDigests.new(user).send(:recent_years_with_stats)
            { 'now' => instant, 'ambient_zone' => zone, 'user_zone' => 'Asia/Tokyo', 'years' => years }
          end
        end
      end
    end

    def cache_staleness
      %w[missing blank nil_patterns false_patterns fresh equal older no_latest].map do |state|
        cache_isolated do
          user = cache_user
          cache_stat(user, 2025) unless state == 'no_latest'
          patterns = case state
                     when 'blank' then {}
                     when 'nil_patterns' then nil
                     when 'false_patterns' then false
                     else { 'weekly_pattern' => [1, 2, 3, 4, 5, 6, 7] }
                     end
          stamp = if state == 'older'
                    now - 1.second
                  else
                    now + (state == 'fresh' ? 1.second : 0)
                  end
          digest = cache_digest(user, 2025, patterns, stamp) unless state == 'missing'
          stale = digest.nil? || Cache::PreheatInsightsDigests.new(user).send(:digest_stale?, digest, 2025)
          expect(stale).to eq(%w[missing blank nil_patterns false_patterns older].include?(state))
          Cache::PreheatInsightsDigests.new(user).call
          saved = user.digests.yearly.first
          { 'state' => state, 'stale' => stale, 'distance' => saved&.distance,
            'updated_at' => saved&.updated_at&.iso8601, 'key' => saved && cache_key(user, saved) }
        end
      end
    end

    def cache_warming
      user = cache_user
      other = cache_user(180_102)
      cache_stat(user, 2025)
      cache_digest(user, 2025)
      writes = []
      listener = ->(*, payload) { writes << payload.slice(:key, :expires_in) }
      ActiveSupport::Notifications.subscribed(listener, 'cache_write.active_support') do
        Cache::PreheatingJob.new.perform
        Cache::UserPreheatingJob.new.perform(user.id)
      end
      one_day = %w[years_tracked points_geocoded_stats countries_visited cities_visited total_distance]
      expected = one_day.map { |suffix| "dawarich/user_#{user.id}_#{suffix}" }
      user_writes = writes.select { |write| expected.include?(write[:key]) }
      expect(user_writes.map { |write| write[:key] }.uniq.sort).to eq(expected.sort)
      expect(user_writes.map { |write| write[:expires_in].to_i }.uniq).to eq([86_400])
      expect(writes.find { |write| write[:key] == 'dawarich/countries_codes' }[:expires_in]).to eq(86_400)
      yearly = cache_key(user, user.digests.yearly.first)
      expect(writes.find { |write| write[:key] == yearly }[:expires_in]).to eq(3600)
      Rails.cache.write("dawarich/user_#{other.id}_total_distance", 99, expires_in: 1.day)
      Cache::InvalidateUserCaches.new(user.id, year: 2025).call
      invalidated = (expected + [yearly]).index_with { |key| Rails.cache.exist?(key) }
      expect(invalidated.values).to eq([true, false, false, false, false, false])
      expect(Rails.cache.read("dawarich/user_#{other.id}_total_distance")).to eq(99)
      { 'writes' => writes.map { |write| { 'key' => write[:key], 'ttl' => write[:expires_in].to_i } },
        'invalidated' => invalidated, 'other_user_distance' => 99 }
    end

    def cache_controller(user, year = 2025)
      InsightsController.new.tap do |controller|
        allow(controller).to receive(:current_user).and_return(user)
        controller.instance_variable_set(:@selected_year, year)
      end
    end

    def cache_readers
      %w[warm stale_snapshot cached_nil cold corrupt failure missing no_stats].map do |state|
        cache_isolated do |cache|
          user = cache_user
          cache_stat(user, 2025) unless state == 'no_stats'
          digest = cache_digest(user, 2025) unless %w[missing no_stats].include?(state)
          key = digest && cache_key(user, digest)
          if %w[warm stale_snapshot cached_nil].include?(state)
            Rails.cache.write(key, state == 'cached_nil' ? nil : digest, expires_in: 1.hour)
            digest.update_columns(distance: 888) if state == 'stale_snapshot'
          elsif state == 'corrupt'
            cache_remember(cache, key)
            cache_redis { |redis| redis.set(key, 'corrupt fixture', ex: 3600) }
          elsif key
            Rails.cache.delete(key)
          end
          cache_redis do |redis|
            if state == 'failure'
              allow(redis).to receive(:get).with(key).and_raise(Redis::CannotConnectError,
                                                                'synthetic unavailable')
            end
          end
          calls = 0
          allow(Users::Digests::CalculateYear).to receive(:new).and_wrap_original do |original, *args|
            calls += 1
            original.call(*args)
          end
          result = cache_controller(user).send(:fetch_or_calculate_yearly_digest)
          expect(result&.distance).to eq(if %w[cached_nil no_stats].include?(state)
                                           nil
                                         else
                                           state == 'missing' ? 1000 : 777
                                         end)
          { 'state' => state, 'distance' => result&.distance, 'calculation_calls' => calls,
            'activity_pairs' => result&.travel_patterns&.fetch('activity_breakdown', {})&.to_a }
        end
      end
    end

    def cache_missing_users
      [180_199, 180_101].map do |id|
        cache_isolated do
          cache_user(id, deleted_at: now) if id == 180_101
          before = Users::Digest.count
          Cache::UserPreheatingJob.new.perform(id)
          expect(Users::Digest.count).to eq(before)
          { 'state' => id == 180_101 ? 'deleted' : 'missing', 'digest_delta' => Users::Digest.count - before }
        end
      end
    end

    def cache_failures
      [1, 2].map do |failure_at|
        cache_isolated do
          user = cache_user
          [2025, 2023, 2022].each { |year| cache_stat(user, year) }
          calls = []
          logs = []
          allow(Rails.logger).to receive(:error) { |message| logs << message }
          allow(Users::Digests::CalculateYear).to receive(:new).and_wrap_original do |original, id, year|
            calls << year
            raise 'synthetic calculation failure' if calls.length == failure_at

            original.call(id, year)
          end
          Cache::PreheatInsightsDigests.new(user).call
          expect(logs).to eq(["Failed to preheat insights digest for user #{user.id}: synthetic calculation failure"])
          expect(calls).to eq(failure_at == 1 ? [2025] : [2025, 2023])
          { 'failure_at' => failure_at, 'calls' => calls, 'saved_years' => user.digests.pluck(:year),
'log_count' => logs.length }
        end
      end
    end

    def cache_eligibility
      [false, true].map do |self_hosted|
        cache_isolated do
          [0, 1, 2, 3].each { |status| cache_user(180_101 + status, status:) }
          cache_user(180_105, deleted_at: now)
          allow(DawarichSettings).to receive(:self_hosted?).and_return(self_hosted)
          ids = Cache::PreheatingJob.new.send(:target_users).where(id: 180_101..180_105).order(:id).pluck(:id)
          expect(ids).to eq(self_hosted ? [180_101, 180_102, 180_103, 180_104] : [180_102, 180_103])
          { 'self_hosted' => self_hosted, 'user_ids' => ids }
        end
      end
    end

    def cache_http_scoping
      user = cache_user(plan: 0)
      cache_stat(user, 2025, 1, now + 1.day)
      cache_stat(user, 2025, 11, now)
      digest = cache_digest(user, 2025)
      controller = cache_controller(user)
      preheat = Cache::PreheatInsightsDigests.new(user).send(:digest_stale?, digest, 2025)
      http = controller.send(:digest_stale?, digest)
      expect([preheat, http]).to eq([true, false])
      monthly = Users::Digest.create!(user:, year: 2025, month: 11, period_type: :monthly,
                                      travel_patterns: {}, created_at: now, updated_at: now)
      equal = controller.send(:monthly_digest_stale?, monthly)
      monthly.update_columns(updated_at: now - 1.second)
      older = controller.send(:monthly_digest_stale?, monthly)
      expect([equal, older]).to eq([false, true])
      controller.params = ActionController::Parameters.new(month: '3')
      controller.send(:load_monthly_digest)
      expect(controller.instance_variable_get(:@monthly_digest)).to be_nil
      { 'preheat_stale' => preheat, 'http_stale' => http,
        'scoped_months' => user.scoped_stats.order(:month).pluck(:month),
        'monthly_equal_blank' => equal, 'monthly_older' => older, 'unavailable_month_digest' => nil }
    end

    def cache_fragments
      user = cache_user
      cache_stat(user, 2025)
      countries = [[180_901, 'AA', 'AAA'], [180_902, 'BB', 'BBB']].map do |id, iso_a2, iso_a3|
        { id:, name: 'Duplicate', iso_a2:, iso_a3:, created_at: now, updated_at: now }
      end
      Country.insert_all!(countries)
      Rails.cache.delete(Country::NAMES_TO_ISO_A2_CACHE_KEY)
      writes = []
      listener = ->(*, payload) { writes << payload.slice(:key, :expires_in) }
      InsightsController.perform_caching = true
      ActiveSupport::Notifications.subscribed(listener, 'cache_write.active_support') do
        codes = Country.names_to_iso_a2
        expect(codes['Duplicate']).to eq('BB')
        sign_in user
        get '/insights/details?year=2025&month=1', headers: { 'Turbo-Frame' => 'insights_details' }
        expect(response).to have_http_status(:ok)
      end
      fragments = writes.select { |write| write[:key].start_with?('views/insights/details:') }
      expect(fragments.length).to eq(6)
      expect(fragments.map { |write| write[:expires_in].to_i }.uniq).to eq([86_400])
      { 'country_key' => Country::NAMES_TO_ISO_A2_CACHE_KEY, 'country_ttl' => 86_400,
        'country_pairs' => Country.names_to_iso_a2.to_a,
        'fragments' => fragments.map { |write| { 'key' => write[:key], 'ttl' => write[:expires_in].to_i } } }
    end

    def cache_trigger
      original = ENV['TZ']
      entry = YAML.load_file(Rails.root.join('config/schedule.yml')).fetch('cache_preheating_job')
      ENV.delete('TZ')
      ['2025-01-01T00:00:00Z', '2025-07-01T00:00:00Z'].map do |instant|
        Time.use_zone('Europe/Berlin') do
          cron = Sidekiq::Cron::Job.allocate.send(:do_parse_cron, entry.fetch('cron'))
          native_cron = Fugit::Cron.parse('0 0 * * * Etc/UTC')
          { 'cron' => entry.fetch('cron'), 'ambient_zone' => Time.zone.name, 'after' => instant,
            'rails_fires_at' => cron.next_time(Time.iso8601(instant)).to_t.utc.iso8601,
            'oban_utc_fires_at' => native_cron.next_time(Time.iso8601(instant)).to_t.utc.iso8601 }
        end
      end
    ensure
      original ? ENV['TZ'] = original : ENV.delete('TZ')
    end

    it 'writes or matches A12d1b4 cache retirement corpus twice byte-identically' do
      corpus = cache_capture
      expect(corpus.fetch('completed_years').map do |kase|
        kase.fetch('years')
      end).to eq([[2025, 2023], [2025, 2023], [2023, 2022]])
      first = digest_json(corpus)
      expect(digest_json(cache_capture)).to eq(first)
      destination = Rails.root.join('app-phoenix/test/fixtures/a12d1b4/cache.json')
      if ENV['WRITE_PHOENIX_FIXTURES'] == '1'
        FileUtils.mkdir_p(destination.dirname)
        File.write(destination, first)
      else
        expect(first).to eq(destination.read)
      end
    end
  end
end
