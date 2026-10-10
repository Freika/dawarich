# frozen_string_literal: true

require 'rails_helper'
require_relative 'fixture_recording'

RSpec.describe 'Phoenix fixture: ISO codes and flags of Countries::IsoCodeMapper' do
  it 'writes priv/country_codes.json in COUNTRIES order' do
    countries = Countries::IsoCodeMapper::COUNTRIES
    expect(countries.all? { |key, data| key == data[:iso2] }).to be(true)

    path = Rails.root.join('app-phoenix/priv/country_codes.json')
    rows = countries.values.map { |data| [data[:name], data[:iso2], data[:iso3], data[:flag]] }
    data = { 'countries' => rows }
    data.merge!(JSON.parse(path.read).slice('borders_gzip_base64', 'visited_aliases')) if path.exist?
    data.compact!
    File.write(path, "#{Oj.dump(data, mode: :strict, indent: 2)}\n")

    expect(JSON.parse(path.read)['countries'].size).to eq(countries.size)
    expect(Countries::IsoCodeMapper.iso_codes_from_country_name('Russia')).to eq(%w[RU RUS])
    expect(Countries::IsoCodeMapper.iso_codes_from_country_name('germany')).to eq(%w[DE DEU])
    expect(Countries::IsoCodeMapper.iso_codes_from_country_name('Atlantis')).to eq([nil, nil])
  end
end

module ApiStatsGoldenOracle
  TABLES = %w[users countries stats digests visits points flights].freeze
  JSON_ACCEPT = { 'Accept' => 'application/json' }.freeze
  NY = { timezone: 'America/New_York' }.freeze
  UTC = { timezone: 'UTC' }.freeze
  CITIES = '/api/v1/countries/visited_cities'
  FLIGHTS = '/api/v1/flights'
  CASES = [
    { name: 'stats_bearer_json', path: '/api/v1/stats', seed: :stats },
    { name: 'stats_query_key_no_accept', path: '/api/v1/stats', seed: :stats, auth: :query, accept: false },
    { name: 'stats_empty', path: '/api/v1/stats' },
    { name: 'stats_format_param', path: '/api/v1/stats?format=json', headers: { 'Accept' => 'text/html' } },
    { name: 'stats_if_none_match_hit', path: '/api/v1/stats', seed: :stats, conditional: :etag },
    { name: 'insights_default_year', path: '/api/v1/insights', seed: :insights },
    { name: 'insights_year_mi', path: '/api/v1/insights?year=2023&distance_unit=mi', seed: :insights },
    { name: 'insights_setting_unit_ft', path: '/api/v1/insights?year=2024', seed: :insights,
      user: { settings: { 'maps' => { 'distance_unit' => 'ft' } } } },
    { name: 'insights_empty_year', path: '/api/v1/insights?year=2020', seed: :insights },
    { name: 'insights_array_daily', path: '/api/v1/insights?year=2024', seed: :array_daily },
    { name: 'insights_if_none_match_hit', path: '/api/v1/insights', seed: :insights, conditional: :etag },
    { name: 'insights_details_comparison', path: '/api/v1/insights/details', seed: :insights },
    { name: 'insights_details_empty', path: '/api/v1/insights/details?year=2024', seed: :one_stat },
    { name: 'digests_index', path: '/api/v1/digests?distance_unit=km', seed: :digests },
    { name: 'digests_index_utc', path: '/api/v1/digests', seed: :digests, user: UTC },
    { name: 'digest_show', path: '/api/v1/digests/2024?distance_unit=km', seed: :digests },
    { name: 'digest_show_mi_moon', path: '/api/v1/digests/2023?distance_unit=mi', seed: :digests },
    { name: 'digest_show_defaults', path: '/api/v1/digests/2022', seed: :empty_digest },
    { name: 'digest_show_missing', path: '/api/v1/digests/2021', seed: :digests },
    { name: 'digest_show_foreign', path: '/api/v1/digests/2024', seed: :foreign_digest },
    { name: 'digest_show_if_modified_since_hit', path: '/api/v1/digests/2024', seed: :digests,
      conditional: :last_modified },
    { name: 'digest_show_if_modified_since_older', path: '/api/v1/digests/2024', seed: :digests, conditional: :older },
    { name: 'digest_show_if_none_match_and_since', path: '/api/v1/digests/2024', seed: :digests, conditional: :both },
    { name: 'residency_year', path: '/api/v1/residency?year=2025', seed: :residency },
    { name: 'residency_default_year', path: '/api/v1/residency', seed: :residency },
    { name: 'residency_empty', path: '/api/v1/residency?year=2023', seed: :residency },
    { name: 'cities_epoch', path: "#{CITIES}?start_at=1699999999&end_at=1702000000", seed: :cities },
    { name: 'cities_iso_offset', path: "#{CITIES}?start_at=2023-11-14T00:00%2B01:00&end_at=2023-12-31T00:00%2B01:00",
      seed: :cities },
    { name: 'cities_numeric_clamp', path: "#{CITIES}?start_at=0&end_at=9999999999", seed: :cities, user: NY },
    { name: 'cities_missing', path: CITIES },
    { name: 'cities_missing_end', path: "#{CITIES}?start_at=1&end_at=" },
    { name: 'cities_min_minutes_setting', path: "#{CITIES}?start_at=1699999999&end_at=1702000000", seed: :cities,
      user: { settings: { 'min_minutes_spent_in_city' => '10' } } },
    { name: 'flights_all', path: FLIGHTS, seed: :flights, user: NY },
    { name: 'flights_range_offset', seed: :flights_range,
      path: "#{FLIGHTS}?start_at=2024-03-01T00:00%2B01:00&end_at=2024-03-31T23:59%2B02:00" },
    { name: 'flights_range_dates', path: "#{FLIGHTS}?start_at=2024-03-01&end_at=2024-03-31", seed: :flights_range },
    { name: 'flights_start_only', path: "#{FLIGHTS}?start_at=2024-03-01", seed: :flights_range },
    { name: 'flights_utc', path: FLIGHTS, seed: :flights, user: UTC },
    { name: 'auth_missing', path: '/api/v1/stats', auth: :none },
    { name: 'auth_unknown_insights', path: '/api/v1/insights', auth: :unknown },
    { name: 'auth_pending_digests', path: '/api/v1/digests', user: { status: 'pending_payment' } },
    { name: 'auth_inactive_flights', path: FLIGHTS, user: { status: 'inactive' } },
    { name: 'auth_expired_residency', path: '/api/v1/residency?year=2025',
      user: { active_until: Time.utc(2001, 1, 1) } },
    { name: 'request_id_valid', path: '/api/v1/stats', headers: { 'X-Request-Id' => 'phoenix-a4g2-req_1@golden' } },
    { name: 'zone_rails_alias', path: '/api/v1/digests', seed: :digests, user: { timezone: 'Berlin' } },
    { name: 'replay_zone_case', expect: :rails, path: '/api/v1/digests', seed: :digests,
      user: { timezone: 'europe/berlin' } },
    { name: 'replay_insights_year_shape', expect: :rails, path: '/api/v1/insights?year=abc', seed: :insights },
    { name: 'replay_residency_year_1969', expect: :rails, path: '/api/v1/residency?year=1969' },
    { name: 'replay_residency_tie', expect: :rails, path: '/api/v1/residency?year=2025', seed: :residency_tie },
    { name: 'replay_cities_loose_date', expect: :rails, path: "#{CITIES}?start_at=Nov%2014%202023&end_at=1702000000",
      seed: :cities },
    { name: 'replay_flights_loose_date', expect: :rails, path: "#{FLIGHTS}?start_at=March%201%202024",
      seed: :flights_range },
    { name: 'replay_digest_since_rfc850', expect: :rails, path: '/api/v1/digests/2024', seed: :digests,
      headers: { 'If-Modified-Since' => 'Sunday, 06-Nov-94 08:49:37 GMT' } },
    { name: 'replay_digest_toponyms_string_element', expect: :rails, path: '/api/v1/digests/2024', seed: :odd_digest },
    { name: 'replay_client_header', expect: :rails, path: '/api/v1/stats', headers: { 'X-Dawarich-Client' => 'ios' },
      ignore: ['set-cookie'] },
    { name: 'rails_head_stats', expect: :rails, method: :head, path: '/api/v1/stats' },
    { name: 'rails_stats_json_suffix', expect: :rails, path: '/api/v1/stats.json' },
    { name: 'rails_cloud_stats', expect: :rails, path: '/api/v1/stats', env: { 'SELF_HOSTED' => 'false' } },
    { name: 'rails_digest_year_suffix', expect: :rails, path: '/api/v1/digests/2024.json', seed: :digests,
      auth: :none },
    { name: 'rails_digest_post_valid', expect: :rails, method: :post, path: '/api/v1/digests?year=2023',
      seed: :previous_stat },
    { name: 'rails_digest_post_existing', expect: :rails, method: :post, path: '/api/v1/digests?year=2024',
      seed: :digests },
    { name: 'rails_digest_delete', expect: :rails, method: :delete, path: '/api/v1/digests/2024', seed: :digests },
    { name: 'rails_digest_delete_inactive', expect: :rails, method: :delete, path: '/api/v1/digests/2024',
      seed: :digests, user: { status: 'inactive' } },
    { name: 'rails_borders_anonymous', expect: :rails, path: '/api/v1/countries/borders', auth: :none },
    { name: 'rails_visited_epoch', expect: :rails, seed: :cities,
      path: '/api/v1/countries/visited?start_at=1699999999&end_at=1702000000' }
  ].freeze

  def self.results
    @results ||= []
  end
end

RSpec.describe 'Phoenix fixture: golden stats API requests', type: :request do
  let(:fixture_models) { [User, Country, Stat, Users::Digest, Visit, Point, Flight] }
  include FixtureRecording::DeterministicInputs
  after(:all) do
    path = Rails.root.join('app-phoenix/test/fixtures/api_stats/golden.json')
    FileUtils.mkdir_p(path.dirname)
    fixture = { 'time_zone' => ENV.fetch('TIME_ZONE', nil),
                'cases' => ApiStatsGoldenOracle.results.sort_by { _1['name'] } }
    File.write(path, "#{g2_exact_json(fixture)}\n")
    if (visited = fixture['cases'].find { _1['name'] == 'rails_visited_epoch' })
      recorded = visited.merge('expect' => 'own', 'cache' => self.class.instance_variable_get(:@visited_epoch_cache))
      File.write(path.dirname.join('visited_epoch.json'), "#{g2_exact_json(recorded)}\n")
    end
  end

  ApiStatsGoldenOracle::CASES.each do |kase|
    it(kase[:name]) do
      defaults = { method: :get, auth: :bearer, expect: :own, env: {}, seed: :none, user: {} }
      recorded = g2_record(kase.reverse_merge(defaults))
      ApiStatsGoldenOracle.results << recorded
      if kase[:name] == 'rails_visited_epoch'
        user = recorded['setup'].find { _1.first == 'users' }.last.find do |row|
          row['api_key'] == recorded['request']['headers'].to_h['Authorization'].delete_prefix('Bearer ')
        end
        keys = [2023, 'all'].map { "points:tile_epoch:#{user['id']}:#{_1}" }
        self.class.instance_variable_set(:@visited_epoch_cache, keys.index_with { Rails.cache.read(_1, raw: true) })
      end
    end
  end

  def g2_exact_json(value, depth = 0)
    pad = '  ' * (depth + 1)
    case value
    when Hash
      return '{}' if value.empty?

      entries = value.map { |k, v| "#{pad}#{Oj.dump(k.to_s, mode: :strict)}: #{g2_exact_json(v, depth + 1)}" }
      "{\n#{entries.join(",\n")}\n#{'  ' * depth}}"
    when Array
      return '[]' if value.empty?

      entries = value.map { |v| "#{pad}#{g2_exact_json(v, depth + 1)}" }
      "[\n#{entries.join(",\n")}\n#{'  ' * depth}]"
    when Float
      value.to_s
    else
      Oj.dump(value, mode: :strict)
    end
  end

  def g2_user(kase)
    attrs = { status: 'active', active_until: nil, timezone: 'Europe/Berlin', settings: {} }.merge(kase[:user])
    user = create(:user)
    settings = user.settings.merge('timezone' => attrs[:timezone]).merge(attrs[:settings])
    user.update_columns(api_key: "phoenix-a4g2-golden-key-#{kase[:name]}", status: User.statuses.fetch(attrs[:status]),
                        active_until: attrs[:active_until], settings:)
    user
  end

  def g2_record(kase)
    user = g2_user(kase)
    send("g2_seed_#{kase[:seed]}", user)
    allow(DawarichSettings).to receive(:self_hosted?).and_return(false) if kase[:env]['SELF_HOSTED'] == 'false'
    headers = g2_headers(kase, user)
    path = kase[:auth] == :query ? "#{kase[:path]}?api_key=#{user.api_key}" : kase[:path]
    g2_conditional(kase[:conditional], path, headers) if kase[:conditional]
    if kase[:name] == 'rails_visited_epoch'
      [2023, 'all'].each { Rails.cache.delete("points:tile_epoch:#{user.id}:#{_1}") }
    end
    setup = ApiStatsGoldenOracle::TABLES.map do |table|
      rows = ActiveRecord::Base.connection.select_values("SELECT row_to_json(t)::text FROM #{table} t ORDER BY id")
      [table, rows.map { JSON.parse(_1) }]
    end

    send(kase[:method], path, headers: headers)

    { 'name' => kase[:name], 'expect' => kase[:expect].to_s, 'ignore' => kase[:ignore] || [],
      'env' => kase[:env], 'setup' => setup,
      'request' => { 'method' => kase[:method].to_s.upcase, 'target' => path, 'headers' => headers.to_a },
      'response' => { 'status' => response.status, 'body' => response.body,
                      'headers' => response.headers.to_h.transform_keys(&:downcase).except('date', 'content-length') } }
  end

  def g2_headers(kase, user)
    accept = kase[:accept] == false ? {} : ApiStatsGoldenOracle::JSON_ACCEPT
    headers = { 'Host' => 'localhost' }.merge(accept).merge(kase[:headers] || {})
    headers['Authorization'] = "Bearer #{user.api_key}" if kase[:auth] == :bearer
    headers['Authorization'] = 'Bearer phoenix-a4g2-golden-unknown' if kase[:auth] == :unknown
    headers
  end

  def g2_conditional(kind, path, headers)
    get path, headers: headers
    case kind
    when :etag then headers['If-None-Match'] = response.headers['ETag']
    when :last_modified then headers['If-Modified-Since'] = response.headers['Last-Modified']
    when :older then headers['If-Modified-Since'] = (Time.httpdate(response.headers['Last-Modified']) - 86_400).httpdate
    when :both then headers.merge!('If-Modified-Since' => response.headers['Last-Modified'],
                                   'If-None-Match' => 'W/"phoenix-a4g2"')
    end
  end

  def g2_toponym(country, *cities) = { 'country' => country, 'cities' => cities.map { { 'city' => _1 } } }

  def g2_points(user, rows) = rows.each { |attrs| create(:point, user:, **attrs) }

  def g2_seed_none(_user); end

  def g2_seed_stats(user)
    create(:stat, user:, year: 2024, month: 1, distance: 1999,
                  toponyms: [g2_toponym('Germany', 'Berlin', 'Munich'),
                             { 'country' => nil, 'cities' => [{ 'city' => 'Nowhere' }] }])
    create(:stat, user:, year: 2024, month: 12, distance: 2001,
                  toponyms: [[g2_toponym('France', 'Paris')], { 'country' => ' ', 'cities' => [{ 'city' => 'Blank' }] },
                             { 'country' => 7 }])
    create(:stat, user:, year: 2025, month: 3, distance: 999, toponyms: [g2_toponym('Germany')])
    geocoded = (1..3).map { { timestamp: 1_700_000_000 + _1, reverse_geocoded_at: Time.utc(2026, 1, 1) } }
    g2_points(user, geocoded + [{ timestamp: 1_700_000_100 }])
  end

  def g2_seed_insights(user)
    create(:stat, user:, year: 2024, month: 3, distance: 12_345, toponyms: [g2_toponym('Germany', 'Berlin')],
                  daily_distance: { '1' => 5000, '2' => 7345, '3' => 0 })
    create(:stat, user:, year: 2024, month: 7, distance: 50_000,
                  toponyms: [g2_toponym('France', 'Paris', 'Lyon'), g2_toponym('Germany', 'Hamburg')],
                  daily_distance: { '14' => 50_000 })
    create(:stat, user:, year: 2023, month: 5, distance: 1000, toponyms: [g2_toponym('Germany', 'Berlin')],
                  daily_distance: { '3' => 1000 })
    create(:stat, user:, year: 2023, month: 6, distance: 1000, toponyms: [], daily_distance: [])
    create(:users_digest, user:, year: 2024,
                          travel_patterns: { 'time_of_day' => { 'morning' => 10, 'night' => 2, 'afternoon' => 5 },
                                             'seasonality' => nil, 'activity_breakdown' => { 'walking' => 1 } })
    create(:users_digest, user:, year: 2024, month: 3, period_type: :monthly,
                          monthly_distances: { '1' => 5000, '2' => 7345 })
    create(:users_digest, user:, year: 2024, month: 7, period_type: :monthly, monthly_distances: [[14, 50_000]])
    visits = [['Cafe', Time.utc(2024, 2, 1, 10), 10, 1], ['Cafe', Time.utc(2023, 12, 31, 23, 30), 40, 1],
              ['Cafe', Time.utc(2024, 6, 1, 10), 1, 2], ['Office', Time.utc(2024, 3, 1, 9), 100, 1],
              ['Office', Time.utc(2024, 12, 31, 23, 30), 100, 1], ['Gym', Time.utc(2024, 5, 1, 18), 500, 1]]
    Visit.insert_all(visits.map do |name, at, duration, status|
      { user_id: user.id, name:, started_at: at, ended_at: at, duration:, status:,
        created_at: Time.current, updated_at: Time.current }
    end)
  end

  def g2_seed_array_daily(user)
    create(:stat, user:, year: 2024, month: 3, distance: 450, daily_distance: [[2, 100], [1, 50], [2, 300], ['1', 7]])
    create(:stat, user:, year: 2024, month: 2, distance: 13, daily_distance: { '1' => 4, '30' => 9 })
  end

  def g2_seed_one_stat(user) = create(:stat, user:, year: 2024, month: 3, distance: 1000)
  def g2_seed_previous_stat(user) = create(:stat, user:, year: 2023, month: 5, distance: 1000)

  def g2_seed_digests(user)
    [2022, 2023, 2024, 2026].each { |year| create(:stat, user:, year:, month: 1, distance: 1) }
    create(:users_digest, user:, year: 2024, created_at: Time.utc(2025, 1, 2, 3, 4, 5),
                          updated_at: Time.utc(2025, 1, 2, 3, 4, 5.678r),
                          time_spent_by_location: { 'countries' => [{ 'name' => 'Germany', 'minutes' => 100 }],
                                                    'total_country_minutes' => 100 },
                          first_time_visits: { 'countries' => [], 'cities' => ['Hamburg'] },
                          year_over_year: { 'distance_change_percent' => 12.5, 'countries_change' => 1,
                                            'cities_change' => -2 },
                          all_time_stats: { 'total_countries' => 3, 'total_cities' => 5, 'total_distance' => 2.5e7 },
                          travel_patterns: { 'time_of_day' => { 'morning' => 2, 'night' => 1 },
                                             'seasonality' => false })
    create(:users_digest, user:, year: 2023, distance: 400_000_000, created_at: Time.utc(2024, 7, 1, 10),
                          updated_at: Time.utc(2024, 7, 1, 10))
    create(:users_digest, user:, year: 2999)
    create(:users_digest, user:, year: 2025, month: 1, period_type: :monthly)
  end

  def g2_seed_empty_digest(user)
    create(:users_digest, user:, year: 2022, distance: 0, toponyms: {}, monthly_distances: {},
                          time_spent_by_location: {}, first_time_visits: {}, year_over_year: {}, all_time_stats: {},
                          travel_patterns: {},
                          created_at: Time.utc(2023, 1, 1), updated_at: Time.utc(2023, 1, 1))
  end

  def g2_seed_foreign_digest(_user)
    foreign = g2_foreign_user
    create(:users_digest, user: foreign, year: 2024)
  end

  def g2_foreign_user
    foreign = create(:user)
    foreign.update_columns(api_key: 'phoenix-a4g2-golden-key-foreign')
    foreign
  end

  def g2_seed_odd_digest(user)
    create(:users_digest, user:, year: 2024, toponyms: ['x', g2_toponym('Germany', 'Berlin')],
                          created_at: Time.utc(2025, 6, 1), updated_at: Time.utc(2025, 6, 1))
  end

  def g2_seed_residency(user)
    [2024, 2025].each { |year| create(:stat, user:, year:, month: 1, distance: 1) }
    days = [[Time.utc(2024, 12, 31, 23, 30), 'Germany'], [Time.utc(2025, 1, 1, 12), 'Germany'],
            [Time.utc(2025, 1, 2, 12), 'Germany'], [Time.utc(2025, 1, 3, 12), 'Germany'],
            [Time.utc(2025, 1, 10, 8), 'Germany'], [Time.utc(2025, 1, 10, 9), 'Germany'],
            [Time.utc(2025, 1, 10, 12), 'France'], [Time.utc(2025, 1, 11, 12), 'France'],
            [Time.utc(2025, 3, 1, 12), 'Czechia'], [Time.utc(2025, 3, 5, 12), 'Atlantis'],
            [Time.utc(2025, 3, 6, 12), 'Atlantis'], [Time.utc(2025, 3, 7, 12), 'Atlantis'],
            [Time.utc(2025, 12, 31, 23, 30), 'Germany']]
    excluded = [{ timestamp: Time.utc(2025, 2, 1, 12).to_i, country_name: 'Germany', anomaly: true },
                { timestamp: Time.utc(2025, 2, 2, 12).to_i, country_name: '' }]
    g2_points(user, days.map { |at, country| { timestamp: at.to_i, country_name: country } } + excluded)
  end

  def g2_seed_residency_tie(user)
    g2_points(user, [{ timestamp: Time.utc(2025, 1, 1, 12).to_i, country_name: 'Germany' },
                     { timestamp: Time.utc(2025, 1, 2, 12).to_i, country_name: 'France' }])
  end

  def g2_seed_cities(user)
    germany = create(:country, name: 'Germany', iso_a2: 'DE', iso_a3: 'DEU')
    t0 = 1_700_000_000
    t1 = 1_700_100_000
    t2 = 1_701_000_000
    g2_points(user, [
                { timestamp: t0, city: 'Berlin', country_name: 'Germany', country_id: germany.id },
                { timestamp: t0 + 1800, city: 'Berlin', country_name: 'Deutschland', country_id: germany.id },
                { timestamp: t0 + 3600, city: 'Berlin', country_name: 'Germany', country_id: germany.id },
                { timestamp: t0 + 4000, city: 'Berlin', country_name: 'Germany', velocity: '200' },
                { timestamp: t0 + 4100, city: 'Berlin', country_name: 'Germany', velocity: '200' },
                { timestamp: t0 + 5000, city: 'Berlin', country_name: 'Germany' },
                { timestamp: t0 + 5600, city: 'Berlin', country_name: 'Germany' },
                { timestamp: t0 + 6000, city: 'Potsdam', country_name: 'Germany' },
                { timestamp: t0 + 7000, city: 'Potsdam', country_name: 'Germany' },
                { timestamp: t1, city: 'Munich', country_name: 'Germany' },
                { timestamp: t1 + 3600, city: 'Munich', country_name: 'Germany' },
                { timestamp: t1 + 3600 + 604_801, city: 'Munich', country_name: 'Germany' },
                { timestamp: t1 + 3600 + 604_801 + 1200, city: 'Munich', country_name: 'Germany' },
                { timestamp: t2, city: 'Paris', country_name: 'France' },
                { timestamp: t2 + 3600, city: nil, country_name: 'France' },
                { timestamp: t2 + 5000, city: 'Paris', country_name: 'France', velocity: '150' },
                { timestamp: t2 + 7200, city: 'Paris', country_name: 'France' },
                { timestamp: t2 + 10_000, city: 'Lyon', country_name: 'France', anomaly: true },
                { timestamp: t2 + 17_200, city: 'Lyon', country_name: 'France', anomaly: true }
              ])
  end

  def g2_seed_flights(user)
    create(:flight, user:, departure_time: Time.utc(2024, 3, 1, 10, 0, 0.123999r),
                    arrival_time: Time.utc(2024, 3, 1, 12), flight_date: Date.new(2024, 3, 1), seat: '12A',
                    seat_class: 'economy')
    create(:flight, user:, departure_time: Time.utc(2024, 2, 1, 8), arrival_time: nil, flight_date: nil,
                    distance_km: nil, from_name: nil)
    create(:flight, user:, departure_time: nil, arrival_time: nil, flight_date: Date.new(2024, 1, 15))
    create(:flight, user:, departure_time: Time.utc(2024, 1, 1), to_lat: nil)
    create(:flight, user: g2_foreign_user, departure_time: Time.utc(2024, 1, 1))
  end

  def g2_seed_flights_range(user)
    [[Time.utc(2024, 3, 1, 0, 30), nil], [Time.utc(2024, 2, 29, 22, 30), nil], [nil, Date.new(2024, 3, 1)],
     [nil, Date.new(2024, 2, 29)], [Time.utc(2024, 3, 31, 21, 59, 59), nil], [Time.utc(2024, 3, 31, 22), nil],
     [Time.utc(2024, 6, 1, 10), nil]].each do |departure, date|
      create(:flight, user:, departure_time: departure, arrival_time: departure && (departure + 2.hours),
                      flight_date: date)
    end
  end
end
