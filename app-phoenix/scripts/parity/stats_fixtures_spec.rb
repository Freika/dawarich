# frozen_string_literal: true

require 'rails_helper'
require 'rake'
require_relative 'fixture_recording'
require_relative 'stats_closure_fixtures'

RSpec.describe 'Phoenix fixtures: stats and digests as Rails renders them', type: :request do
  include ActiveSupport::Testing::TimeHelpers
  include StatsClosureFixtures

  let(:root) { Rails.root.join('app-phoenix') }
  let(:fixtures) { root.join('test/fixtures') }
  let(:helper) { ApplicationController.helpers }

  def verify_fixture(path, bytes) = FixtureRecording.verify(path, bytes)

  def write_json(path, data) = verify_fixture(path, "#{JSON.pretty_generate(data)}\n")

  def each_locale(values)
    %w[en de es fr pl ca zh].flat_map do |locale|
      I18n.with_locale(locale) do
        values.map do |value|
          yield(locale, value)
        end
      end
    end
  end

  it 'writes the formatting corpus, the country names and checks phoenix:importmap' do
    allow(File).to receive(:write).and_call_original
    allow(File).to receive(:binwrite).and_call_original
    unless ENV['WRITE_PHOENIX_FIXTURES'] == '1'
      expect(File).not_to receive(:write).with(fixtures.join('stats_corpus.json'), anything)
      expect(File).not_to receive(:binwrite).with(fixtures.join('stats_corpus.json'), anything)
    end
    dates = %w[2024-03-07 2024-12-01 2025-01-31].map { Date.parse(_1) }
    formats = %i[month_name month_year day_month_year month_day_padded short_month_day_padded]
    countries = [%w[Germany DE DEU], %w[Czechia CZ CZE], ['United States of America', 'US', 'USA'],
                 %w[Kosovo -99 -99], %w[Taiwan CN-TW TWN]]
    geom = 'MULTIPOLYGON (((-78.637074 15.862087, -78.640411 15.864, -78.636871 15.867296, -78.637074 15.862087)))'
    countries.each { |name, a2, a3| Country.create!(name:, iso_a2: a2, iso_a3: a3, geom:) }
    Rails.cache.delete(Country::NAMES_TO_ISO_A2_CACHE_KEY)
    names = ['Germany', 'Czechia', 'Czech Republic', 'czechia', 'UK', 'Deutschland', 'Kosovo', 'Taiwan',
             'Atlantis', 'United States', 'Viet Nam', 'Vietnam', '']

    write_json(fixtures.join('stats_corpus.json'), {
                 dates: each_locale(dates.product(formats)) do |locale, (date, format)|
                   { locale:, date: date.iso8601, format:, output: I18n.l(date, format:) }
                 end,
      delimited: each_locale([0, 7, 999, 1000, 70_123, 1_234_567]) do |locale, n|
        { locale:, input: n, output: helper.number_with_delimiter(n) }
      end,
      precision: each_locale([0.0, 12.3, 98.7, 100.0]) do |locale, x|
        { locale:, input: x, output: helper.number_with_precision(x, precision: 1, strip_insignificant_zeros: true) }
      end,
      countries: {
        table: Country.pluck(:name, :iso_a2),
        cases: names.map do |name|
          { input: name, normalized: helper.send(:normalize_country_name, name), flag: helper.country_flag(name).to_s }
        end
      },
      time_spent: each_locale([0, 59, 60, 61, 1439, 1440, 1500, 90.5]) do |locale, m|
        { locale:, input: m, output: helper.format_time_spent(m) }
      end,
      comparison: each_locale([0, 50_000, 40_075_000, 384_400_000, 500_000_000]) do |locale, m|
        { locale:, input: m, output: helper.distance_comparison_text(m) }
      end,
      yoy: [150, -20, 0, 12.5, nil].map do |change|
        { input: change, class: helper.yoy_change_class(change), text: helper.yoy_change_text(change) }
      end,
      chart: helper.column_chart([['März', 12], ['April', nil], [3, 0]], id: 'chart-corpus', height: '200px',
                                 suffix: ' km', xtitle: 'Tage & <Nacht>', colors: ['#397bb5'],
                                 library: { datasets: { borderWidth: 0, bar: { minBarLength: 4 } },
                                            interaction: { mode: 'index', intersect: false } }).to_s
               })

    write_json(root.join('priv/country_names.json'), {
                 names: Countries::IsoCodeMapper::COUNTRIES.values.map { _1[:name] },
      aliases: Countries::IsoCodeMapper::COUNTRY_ALIASES,
      territories: CountryFlagHelper::TERRITORY_CODES
               })

    Rails.application.load_tasks unless Rake::Task.task_defined?('phoenix:importmap')
    Dir.mktmpdir do |dir|
      path = File.join(dir, 'importmap.json')
      Rake::Task['phoenix:importmap'].reenable
      Rake::Task['phoenix:importmap'].invoke(path)
      imports = JSON.parse(File.read(path))['imports']
      expect(imports.keys).to include('chartkick', 'Chart.bundle', '@hotwired/stimulus', 'i18n', 'maplibre-gl',
                                      'controllers/stat_page_controller', 'controllers/sharing_modal_controller',
                                      'controllers/base_controller')
      expect(imports.values).to all(start_with('/'))
    ensure
      Rake::Task['phoenix:importmap'].reenable
    end
  end

  let(:now) { Time.utc(2026, 9, 26, 12, 0, 0) }
  let(:settings) do
    { 'timezone' => 'Europe/Berlin', 'maps' => { 'distance_unit' => 'km' }, 'onboarding_completed' => true }
  end

  around do |example|
    ActionController::Base.allow_forgery_protection = true
    example.run
  ensure
    ActionController::Base.allow_forgery_protection = false
  end

  def reader(id, locale: nil, plan: :pro, status: :active, timezone: 'Europe/Berlin')
    user = create(:user, id:, email: "a5s-#{id}@dawarich.test", changelog_consent: :declined,
                         api_key: "a5s-fixture-api-key-#{id}")
    user.update_columns(settings: settings.merge('timezone' => timezone, 'locale' => locale).compact,
                        plan: User.plans[plan], status: User.statuses[status],
                        active_until: Time.utc(3026, 1, 1), points_count: 77,
                        api_key: "a5s-k-#{user.id}")
    user.reload
  end

  def toponym(country, *cities) = { 'country' => country, 'cities' => cities.map { { 'city' => _1 } } }

  def daily(year, month, distances)
    (1..Date.new(year, month, -1).day).map { |day| [day, distances.fetch(day, 0)] }
  end

  def stat(id, user, year, month, distance, **attrs)
    Stat.create!({ id:, user:, year:, month:, distance:, daily_distance: daily(year, month, {}),
                   toponyms: [], sharing_settings: {}, sharing_uuid: format('00000000-0000-4000-8000-%012d', id),
                   created_at: now - 3.days, updated_at: now - 2.days }.merge(attrs))
  end

  def digest(id, user, year, **attrs)
    Users::Digest.create!({ id:, user:, year:, period_type: :yearly, distance: 50_000, toponyms: [],
                            first_time_visits: {}, time_spent_by_location: {}, year_over_year: {},
                            all_time_stats: {}, monthly_distances: {}, sharing_settings: {},
                            sharing_uuid: format('00000000-0000-4000-9000-%012d', id) }.merge(attrs))
  end

  def geocoding(store_geodata: true)
    InstanceSetting.delete_all
    InstanceSetting.create!(key: 'photon_api_host', value: 'photon.test.example.com')
    InstanceSetting.create!(key: 'store_geodata', value: false) unless store_geodata
    InstanceSettings::Resolver.reset!
  end

  def no_geocoding
    InstanceSetting.delete_all
    InstanceSettings::Resolver.reset!
  end

  def iso(time) = time&.utc&.iso8601(6)

  def original_header_colors
    @original_header_colors ||= ApplicationHelper.instance_method(:header_colors)
  end

  def capture(name, user, path, self_hosted: true, point_counts: { geocoded: 77, without_data: 1 })
    Rails.cache.clear
    allow(DawarichSettings).to receive(:self_hosted?).and_return(self_hosted)
    allow(DawarichSettings).to receive(:store_geodata?).and_return(InstanceSettings::Resolver.value(:store_geodata))
    allow_any_instance_of(StatsQuery).to receive(:cached_points_geocoded_stats).and_return(point_counts)
    colors = original_header_colors
    allow_any_instance_of(ApplicationHelper).to receive(:header_colors) do |instance|
      list = colors.bind(instance).call
      list.define_singleton_method(:sample) { first }
      list
    end
    sign_in user
    get path
    expect(response).to have_http_status(:ok)
    doc = Nokogiri::HTML5(response.body)
    doc.css('input[name="authenticity_token"]').each { |node| node['value'] = 'CSRF' }
    body = doc.at_css('body > div.container > div.w-full > div.flex').inner_html
              .gsub(/token=[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+/, 'token=UPGRADE_TOKEN')
    verify_fixture(fixtures.join("stats/#{name}.html"), body)
    write_json(fixtures.join("stats/#{name}.json"), {
                 path:, title: doc.at_css('title').text, now: now.iso8601, self_hosted:,
      user: { id: user.id, email: user.email, settings: user.settings, plan: User.plans[user.plan],
              status: User.statuses[user.status], active_until: iso(user.active_until), api_key: user.api_key,
              points_count: user.points_count, theme: user.theme },
      stats: user.stats.order(:id).map do |s|
        { id: s.id, year: s.year, month: s.month, distance: s.distance, flight_distance: s.flight_distance,
          daily_distance: s.read_attribute(:daily_distance), toponyms: s.read_attribute(:toponyms),
          sharing_settings: s.sharing_settings, sharing_uuid: s.sharing_uuid,
          created_at: iso(s.created_at), updated_at: iso(s.updated_at) }
      end,
      digests: user.digests.order(:id).map do |d|
        d.attributes.slice(*%w[id year month period_type distance toponyms first_time_visits time_spent_by_location
                               year_over_year all_time_stats monthly_distances sharing_settings sharing_uuid])
         .merge('period_type' => Users::Digest.period_types[d.period_type],
                'created_at' => iso(d.created_at), 'updated_at' => iso(d.updated_at))
      end,
      countries: Country.pluck(:name, :iso_a2, :iso_a3),
      instance_settings: InstanceSetting.order(:id).map { { key: _1.key, value: _1.value } },
      point_counts:
               })
    @closure_reads ||= []
    @closure_reads << { name:, body:, state: JSON.parse(fixtures.join("stats/#{name}.json").read) }
    sign_out user
  end

  def closure_body
    doc = Nokogiri::HTML5(response.body)
    doc.css('input[name="authenticity_token"]').each { _1['value'] = 'CSRF' }
    doc.css('meta[name="csrf-token"]').each { _1['content'] = 'CSRF' }
    doc.css('[nonce]').each { _1['nonce'] = 'NONCE' }
    doc.css('[signed-stream-name]').each { _1['signed-stream-name'] = 'SIGNED_STREAM' }
    FixtureRecording.normalize(doc.to_html)
  end

  def closure_response(method, path, params, user, error = nil)
    {
      self_hosted: DawarichSettings.self_hosted?, method: method.to_s.upcase, path:, params:,
        status: response.status, media_type: response.media_type,
      body: closure_body, location: response.location,
      headers: response.headers.slice('Cache-Control', 'Vary', 'Content-Type', 'X-Frame-Options',
                                      'X-Content-Type-Options', 'Referrer-Policy'),
      cookie: response.headers['Set-Cookie'].present?, flash: flash.to_hash,
      error: error && { class: error.class.name, message: FixtureRecording.normalize(error.message) },
      stats: user.stats.order(:id).map do
        _1.attributes.slice(*%w[id year month distance sharing_uuid sharing_settings])
      end,
      digests: user.digests.order(:id).map do
        _1.attributes.slice(*%w[id year month period_type sharing_uuid sharing_settings])
      end,
      jobs: enqueued_jobs.map { { job: _1[:job].name, args: _1[:args], queue: _1[:queue], at: _1[:at] } }
    }
  end

  def closure_request(user, method, path, params = {}, accept: 'text/html', guest: false)
    reset!
    sign_in user unless guest
    get(guest ? '/users/sign_in' : '/tags/new')
    token = Nokogiri::HTML5(response.body).at_css('meta[name="csrf-token"]')['content']
    clear_enqueued_jobs
    public_send(method, path, params:, headers: { 'Accept' => accept, 'X-CSRF-Token' => token })
    closure_response(method, path, params, user)
  end

  def capture_closure_actions(self_hosted: true)
    allow(DawarichSettings).to receive(:self_hosted?).and_return(self_hosted)
    offset = self_hosted ? 0 : 100
    actor = reader(52_801 + offset)
    other = reader(52_802 + offset)
    stat(528_011 + offset, actor, 2024, 3, 1000)
    stat(528_021 + offset, other, 2024, 3, 1000)
    digest(528_012 + offset, actor, 2024)
    digest(528_013 + offset, actor, 2024, period_type: :monthly, month: 3)
    digest(528_022 + offset, other, 2024)
    Point.insert!({ id: 52_801_001 + offset, user_id: actor.id, timestamp: Time.utc(2024, 3, 1).to_i,
                    lonlat: 'POINT(12.373468 51.339700)', created_at: now, updated_at: now })
    rows = %w[06 07 09 10 11 12 13 14].index_with { [] }
    %w[1 12 all 0 13 bogus].each do |month|
      row = closure_request(actor, :put, "/stats/2024/#{month}/update")
      expect(row[:status]).to eq(month == 'bogus' ? 404 : 303)
      expected = if month == 'all'
                   (1..12).map { [actor.id, '2024', _1] }
                 else
                   (%w[1 12].include?(month) ? [[actor.id, '2024', month]] : [])
                 end
      expect(row[:jobs].map { _1[:args] }).to eq(expected)
      rows['06'] << row
    end
    rows['06'] << closure_request(actor, :post, '/stats/2024/3/update', { _method: 'put' })
    rows['07'] << closure_request(actor, :put, '/stats/update_all')
    expect(rows['07'].last[:jobs].map { _1[:args] }).to eq([[actor.id, 2024, 3]])
    %w[2024 2024junk 1969 2026 9999 bogus].each do |year|
      row = closure_request(actor, :post, '/digests', { year: })
      expect(row[:status]).to eq(303)
      expect(row[:jobs].size).to eq(year.start_with?('2024') ? 1 : 0)
      rows['09'] << row
    end
    %w[missing present].each do |state|
      row = closure_request(actor, :delete, "/digests/#{state == 'missing' ? 1900 : 2024}")
      expect(row[:status]).to eq(state == 'missing' ? 302 : 303)
      expect(other.digests.count).to eq(1)
      expect(actor.digests.monthly.count).to eq(1)
      rows['10'] << row
    end
    digest(528_014 + offset, actor, 2024)
    uuid = "00000000-0000-4000-8000-#{(528_099 + offset).to_s.rjust(12, '0')}"
    allow(SecureRandom).to receive(:uuid).and_return(uuid)
    [['11', '/digests/2024/sharing', '/shared/digest/', actor.digests.yearly.first],
     ['13', '/stats/2024/3/sharing', '/shared/month/', actor.stats.first]].each do |id, path, public_prefix, record|
      ['application/json', 'text/vnd.turbo-stream.html'].each do |accept|
        [{ enabled: '1' }, { enabled: '1', expiration: '12h' }, { enabled: '1', expiration: 'invalid' },
         { enabled: 'true' }, { enabled: '0' }].each do |params|
          row = closure_request(actor, :patch, path, params, accept:)
          expect(row[:status]).to eq(200)
          rows[id] << row
        end
      end
      public_id = id == '11' ? '12' : '14'
      %w[enabled expired disabled missing].each do |state|
        record.enable_sharing!(expiration: '12h')
        if state == 'expired'
          record.update_columns(sharing_settings: record.sharing_settings.merge('expires_at' => (now - 1).iso8601))
        end
        record.disable_sharing! if state == 'disabled'
        uuid = state == 'missing' ? '00000000-0000-4000-8000-000000000000' : record.reload.sharing_uuid
        %i[get head].each do |method|
          row = closure_request(actor, method, public_prefix + uuid, {}, guest: true)
          expect(row[:status]).to eq(state == 'enabled' ? 200 : 302)
          expect(response.body).to eq('') if method == :head
          rows[public_id] << row.merge(grant: state)
        end
      end
      missing = closure_request(actor, :patch, path.sub('2024', '1900'), { enabled: '1' }, accept: 'application/json')
      expect(missing[:status]).to eq(404)
      rows[id] << missing
    end
    @closure_action_cases ||= rows.transform_values { [] }
    rows.each do |id, cases|
      @closure_action_cases[id].concat(cases)
    end
  end

  it 'writes the stats and digest pages' do
    allow(File).to receive(:write).and_call_original
    allow(File).to receive(:binwrite).and_call_original
    unless ENV['WRITE_PHOENIX_FIXTURES'] == '1'
      expect(File).not_to receive(:write).with(fixtures.join('stats/index_lite_en.html'), anything)
      expect(File).not_to receive(:binwrite).with(fixtures.join('stats/index_lite_en.html'), anything)
    end
    allow_any_instance_of(ActionView::Base).to receive(:rand).with(5_000..80_000).and_return(25_000)
    allow(ENV).to receive(:fetch).and_call_original
    allow(ENV).to receive(:fetch).with('JWT_SECRET_KEY').and_return('phoenix-a5-jwt-fixture-secret-not-for-production')
    geom = 'MULTIPOLYGON (((-78.637074 15.862087, -78.640411 15.864, -78.636871 15.867296, -78.637074 15.862087)))'
    [%w[Germany DE DEU], %w[Czechia CZ CZE]].each do |name, a2, a3|
      Country.create!(name:, iso_a2: a2, iso_a3: a3, geom:)
    end

    travel_to now do
      en = reader(5201)
      march = daily(2024, 3, { 5 => 9_000, 6 => 5_400, 7 => 14_000, 20 => 10_000 })
      stat(52_011, en, 2024, 3, 38_400, daily_distance: march, flight_distance: 1_250_000,
                                        toponyms: [toponym('Germany', 'Berlin'), toponym('Czechia', 'Prague')])
      stat(52_012, en, 2024, 4, 12_000, daily_distance: daily(2024, 4, { 10 => 12_000 }),
                                        toponyms: [toponym('Germany', 'Berlin')], updated_at: now - 1.day)
      stat(52_013, en, 2023, 7, 20_000, toponyms: [toponym('Germany', 'Berlin'), toponym('Czech Republic', 'Brno'),
                                                   toponym(nil, 'Nowhere'), { 'country' => 'Austria', 'cities' => [] }])
      stat(52_014, en, 2024, 2, 7_000, daily_distance: daily(2024, 2, { 3 => 7_000 }),
                                       toponyms: [toponym('Germany', 'Berlin'), toponym('Poland', 'Wroclaw', 'Gdansk')])
      geocoding
      capture('index_en', en, '/stats')
      capture('year_en', en, '/stats/2024')
      capture('month_en', en, '/stats/2024/3')
      capture('month_absent_en', en, '/stats/2024/5')
      no_geocoding
      capture('index_nogeo_en', en, '/stats')
      geocoding(store_geodata: false)
      capture('index_nogeodata_en', en, '/stats')

      de = reader(5202, locale: 'de')
      stat(52_021, de, 2024, 3, 38_400, daily_distance: march, toponyms: [toponym('Germany', 'Berlin')],
                                        sharing_settings: { 'enabled' => true, 'expiration' => '12h',
                                                            'expires_at' => (now + 12.hours).iso8601 })
      stat(52_022, de, 2023, 7, 1_234_567, toponyms: [toponym('Germany', 'Berlin')])
      geocoding
      %w[de es fr pl ca zh].each do |locale|
        de.update_columns(settings: de.settings.merge('locale' => locale))
        capture("index_#{locale}", de, '/stats')
        capture("year_#{locale}", de, '/stats/2024')
        capture("month_#{locale}", de, '/stats/2024/3')
      end

      january = reader(5203, timezone: 'UTC')
      stat(52_031, january, 2024, 1, 0, toponyms: [])
      stat(52_032, january, 2023, 12, 5_000, toponyms: [toponym('Germany', 'Berlin')])
      capture('month_january_en', january, '/stats/2024/1')

      empty = reader(5204)
      capture('index_empty_en', empty, '/stats', point_counts: { geocoded: 0, without_data: 0 })

      lite = reader(5205, plan: :lite)
      stat(52_051, lite, 2024, 6, 30_000, toponyms: [toponym('Germany', 'Berlin')])
      stat(52_052, lite, 2025, 8, 8_000, toponyms: [toponym('Germany', 'Berlin')])
      stat(52_053, lite, 2025, 9, 9_000, daily_distance: daily(2025, 9, { 2 => 9_000 }),
                                         toponyms: [toponym('Germany', 'Berlin')])
      stat(52_054, lite, 2026, 2, 4_000, toponyms: [toponym('Germany', 'Berlin')])
      digest(52_055, lite, 2025, distance: 21_000, toponyms: [toponym('Germany', 'Berlin')],
                                 first_time_visits: { 'countries' => ['Germany'], 'cities' => ['Berlin'] })
      capture('index_lite_en', lite, '/stats', self_hosted: false)
      capture('year_lite_en', lite, '/stats/2025', self_hosted: false)
      capture('month_lite_en', lite, '/stats/2025/9', self_hosted: false)
      capture('digest_lite_en', lite, '/digests/2025', self_hosted: false)

      list = reader(5206)
      stat(52_061, list, 2022, 5, 3_000)
      stat(52_062, list, 2023, 5, 3_000)
      stat(52_063, list, 2024, 5, 3_000)
      stat(52_064, list, 2026, 5, 3_000)
      full = {
        distance: 50_000, toponyms: [toponym('Germany', 'Berlin'), toponym('Czechia', 'Prague', 'Brno')],
        first_time_visits: { 'countries' => ['Czechia'], 'cities' => (1..12).map { "City #{_1}" } },
        time_spent_by_location: { 'countries' => [{ 'name' => 'Germany', 'minutes' => 43_200 },
                                                  { 'name' => 'Czechia', 'minutes' => 90 }],
                                  'total_country_minutes' => 43_290 },
        year_over_year: { 'distance_change_percent' => 150, 'previous_year' => 2023 },
        all_time_stats: { 'total_countries' => 2, 'total_cities' => 3, 'total_distance' => '70000' },
        monthly_distances: { '3' => 38_400, '4' => 11_600, '10' => 0 },
        sharing_settings: { 'enabled' => true, 'expiration' => '1w' }
      }
      digest(52_065, list, 2024, **full)
      digest(52_066, list, 2023, distance: 20_000, toponyms: [toponym('Germany', 'Berlin')],
                                 first_time_visits: { 'countries' => ['Germany'], 'cities' => ['Berlin'] })
      digest(52_067, list, 2026, distance: 3_000)
      capture('digests_en', list, '/digests')
      capture('digest_full_en', list, '/digests/2024')

      list_de = reader(5207, locale: 'de')
      stat(52_071, list_de, 2023, 5, 3_000)
      digest(52_072, list_de, 2024, **full)
      %w[de es fr pl ca zh].each do |locale|
        list_de.update_columns(settings: list_de.settings.merge('locale' => locale))
        capture("digests_#{locale}", list_de, '/digests')
        capture("digest_full_#{locale}", list_de, '/digests/2024')
      end

      none = reader(5208)
      stat(52_081, none, 2025, 1, 3_000)
      capture('digests_empty_en', none, '/digests')

      inactive = reader(5209, status: :inactive)
      stat(52_091, inactive, 2025, 1, 3_000)
      capture('digests_inactive_en', inactive, '/digests')

      minimal = reader(5210)
      digest(52_101, minimal, 2024, toponyms: {})
      capture('digest_minimal_en', minimal, '/digests/2024')
      { '01' => /\A(?:index|year)_/, '02' => /\Amonth_/, '08' => /\A(?:digest|digests)_/ }.each do |id, pattern|
        captured = { cases: @closure_reads.select { _1[:name].match?(pattern) } }
        FixtureRecording.source_verify(fixtures.join("stats/a12f3a-q#{id}.json"), JSON.generate(captured))
      end
      hosted = DawarichSettings.self_hosted?
      capture_closure_actions
      capture_closure_actions(self_hosted: false)
      @closure_action_cases.each do |id, cases|
        FixtureRecording.source_verify(fixtures.join("stats/a12f3a-q#{id}.json"), JSON.generate({ cases: }))
      end
      allow(SecureRandom).to receive(:uuid).and_call_original
      allow(DawarichSettings).to receive(:self_hosted?).and_return(hosted)
      capture_q_commands
    end
  end
end
