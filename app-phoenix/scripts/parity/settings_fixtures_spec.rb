# frozen_string_literal: true

require 'rails_helper'
require 'rake'

RSpec.describe 'Phoenix fixtures: settings, account and insights as Rails renders them', type: :request do
  include ActiveSupport::Testing::TimeHelpers

  let(:root) { Rails.root.join('app-phoenix') }
  let(:fixtures) { root.join('test/fixtures') }
  let(:helper) { ApplicationController.helpers }

  def write_json(path, data) = File.write(path, "#{JSON.pretty_generate(data)}\n")

  def qr_entry(payload)
    code = RQRCode::QRCode.new(payload).qrcode
    { payload:, version: code.version, modules: code.modules.map { |row| row.map { _1 ? '1' : '0' }.join },
      svg: ResponsiveQrSvg.call(payload) }
  end

  def heatmap_entry(year, today, months)
    stats = months.map { |month, daily| Stat.new(year:, month:, daily_distance: daily) }
    travel_to(Time.find_zone('Europe/Berlin').local(today.year, today.month, today.day, 12)) do
      Time.use_zone('Europe/Berlin') do
        result = Insights::ActivityHeatmapCalculator.new(stats, year).call
        weeks = helper.heatmap_week_columns(year)
        { year:, today: today.iso8601, stats: months.map { |month, daily| { month:, daily_distance: daily } },
          daily_data: result.daily_data, activity_levels: result.activity_levels, active_days: result.active_days,
          current_streak: result.current_streak, longest_streak: result.longest_streak,
          longest_streak_start: result.longest_streak_start&.iso8601,
          longest_streak_end: result.longest_streak_end&.iso8601,
          weeks: [weeks.first.iso8601, weeks.last.iso8601, weeks.size],
          month_labels: helper.heatmap_month_labels(weeks, year),
          most_recent: helper.most_recent_active_date(result.daily_data),
          levels: result.daily_data.transform_values { helper.calculate_activity_level(_1, result.activity_levels) } }
      end
    end
  end

  it 'writes the corpus and the QR tables and checks phoenix:time_zones' do
    long_key = "a5s3-k-#{'0' * 57}"
    long_host = 'https://a-really-long-self-hosted-instance-name.home.example.org:8443/'
    payloads = [
      { 'server_url' => 'http://www.example.com/', 'api_key' => long_key },
      { 'server_url' => long_host, 'api_key' => long_key },
      { 'server_url' => 'http://localhost:3000/', 'api_key' => 'a5s3-k-1' },
      { 'server_url' => 'http://a.test/?a=1&b=2', 'api_key' => 'k' }
    ].map(&:to_json) + ['otpauth://totp/Dawarich:e2e@dawarich.test?secret=AAAAAAAAAAAAAAAA&issuer=Dawarich',
                        'x', 'hello world', 'a5s3-k-14', 'Grüße aus Köln', 'y' * 300]
    times = [['2026-09-25T10:15:00+00:00', 'Europe/Berlin'], ['2026-01-05T23:30:00Z', 'Europe/Berlin'],
             ['2026-03-08T07:30:00+00:00', 'America/Havana'], ['2026-09-25 10:15:00', 'UTC'],
             ['2026-09-25', 'Asia/Tokyo'], ['not a time', 'UTC'], ['2026-13-45', 'UTC']]
    table = RQRCodeCore::QRRSBlock::RS_BLOCK_TABLE

    write_json(
      root.join('priv/qr_tables.json'),
      max_bits_h: RQRCodeCore::QRMAXBITS[:h],
      rs_blocks_h: (0...40).map { table[(_1 * 4) + 3] },
      positions: RQRCodeCore::QRUtil::PATTERN_POSITION_TABLE
    )

    write_json(
      fixtures.join('settings_corpus.json'),
      time_zone_options: helper.settings_time_zone_options,
      qr: payloads.map { qr_entry(_1) },
      times: times.map do |value, zone|
        parsed = Time.use_zone(zone) do
          Time.zone.parse(value)
        rescue ArgumentError
          nil
        end
        { value:, zone:, output: parsed && I18n.l(parsed, format: :long) }
      end,
      heatmap: [
        heatmap_entry(2024, Date.new(2026, 9, 26),
                      [[3, [[5, 10_000], [6, 5_400], [7, 14_000], [20, 9_000]]], [4, { '10' => 12_000 }]]),
        heatmap_entry(2026, Date.new(2026, 9, 26),
                      [[9, { '24' => 1_000, '25' => 2_000, '26' => 3_000, '-1' => 700 }],
                       [8, [[31, 500], [30, 0], [29, 400]]]]),
        heatmap_entry(2025, Date.new(2026, 9, 26), [[12, [[31, 900]]], [1, [[1, 800], [1, 1_600], [2, '300']]]]),
        heatmap_entry(2023, Date.new(2026, 9, 26), [])
      ]
    )

    Rails.application.load_tasks unless Rake::Task.task_defined?('phoenix:time_zones')
    Dir.mktmpdir do |dir|
      path = File.join(dir, 'time_zones.json')
      Rake::Task['phoenix:time_zones'].invoke(path)
      expect(JSON.parse(File.read(path))['options']).to eq(helper.settings_time_zone_options)
    end
  end

  let(:now) { Time.utc(2026, 9, 26, 12, 0, 0) }

  around do |example|
    ActionController::Base.allow_forgery_protection = true
    example.run
  ensure
    ActionController::Base.allow_forgery_protection = false
  end

  def iso(time) = time&.utc&.iso8601(6)

  def member(id, plan: :pro, status: :active, admin: false, provider: nil, consent: nil, settings: {},
             active_until: Time.utc(3026, 1, 1), source: :none)
    user = create(:user, id:, email: "a5s3-#{id}@dawarich.test", admin:)
    user.update_columns(
      settings: { 'timezone' => 'Europe/Berlin', 'onboarding_completed' => true }.merge(settings),
      plan: User.plans[plan], status: User.statuses[status], active_until:, provider:,
      uid: provider && "a5s3-uid-#{id}", changelog_consent: consent && User.changelog_consents[consent],
      subscription_source: User.subscription_sources[source], points_count: 1_234_567, api_key: "a5s3-k-#{id}"
    )
    user.reload
  end

  def toponym(country, *cities) = { 'country' => country, 'cities' => cities.map { { 'city' => _1 } } }

  def daily(year, month, distances)
    (1..Date.new(year, month, -1).day).map { |day| [day, distances.fetch(day, 0)] }
  end

  def stat(id, user, year, month, distance, **attrs)
    Stat.create!({ id:, user:, year:, month:, distance:, daily_distance: daily(year, month, {}), toponyms: [],
                   sharing_settings: {}, sharing_uuid: format('00000000-0000-4000-8000-%012d', id),
                   created_at: now - 3.days, updated_at: now - 2.days }.merge(attrs))
  end

  def source(id, user, base_url, status: :active, importing: false, last_synced_at: nil, last_error: nil,
             created_at: now - 3.days)
    TripSource.insert_all([{ id:, user_id: user.id, provider: 'trek', base_url:, status: TripSource.statuses[status],
                             importing:, last_synced_at:, last_error:, created_at:, updated_at: created_at }])
  end

  def user_json(user)
    { id: user.id, email: user.email, settings: user.settings, plan: User.plans[user.plan],
      status: User.statuses[user.status], active_until: iso(user.active_until), api_key: user.api_key,
      points_count: user.points_count, theme: user.theme, admin: user.admin, provider: user.provider,
      changelog_consent: user.changelog_consent && User.changelog_consents[user.changelog_consent],
      subscription_source: User.subscription_sources[user.subscription_source] }
  end

  def capture(name, user, path, self_hosted: true, smtp: true, two_factor: false, supporter: { supporter: false })
    Rails.cache.clear
    allow(DawarichSettings).to receive(:self_hosted?).and_return(self_hosted)
    allow(DawarichSettings).to receive(:email_configured?).and_return(smtp)
    allow(DawarichSettings).to receive(:two_factor_available?).and_return(two_factor)
    allow_any_instance_of(Supporter::VerifyEmail).to receive(:call).and_return(supporter)
    allow_any_instance_of(Supporter::VerifyGithubUsername).to receive(:call).and_return(supporter)
    sign_in user
    get path
    expect(response).to have_http_status(:ok)
    doc = Nokogiri::HTML5(response.body)
    doc.css('input[name="authenticity_token"]').each { |node| node['value'] = 'CSRF' }
    body = doc.at_css('body > div.container > div.w-full > div.flex').inner_html
              .gsub(/token=[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+/, 'token=UPGRADE_TOKEN')
    File.write(fixtures.join("settings/#{name}.html"), body)
    write_json(fixtures.join("settings/#{name}.json"), {
                 path:, title: doc.at_css('title').text, now: now.iso8601, self_hosted:, smtp:, two_factor:,
      supporter: supporter.transform_keys(&:to_s), user: user_json(user),
      stats: user.stats.order(:id).map do |s|
        { id: s.id, year: s.year, month: s.month, distance: s.distance,
          daily_distance: s.read_attribute(:daily_distance), toponyms: s.read_attribute(:toponyms),
          created_at: iso(s.created_at), updated_at: iso(s.updated_at) }
      end,
      trip_sources: TripSource.where(user_id: user.id).order(:id).map do |t|
        { id: t.id, provider: t.provider, base_url: t.base_url, importing: t.importing,
          last_synced_at: iso(t.last_synced_at), last_error: t.last_error, status: TripSource.statuses[t.status],
          created_at: iso(t.created_at), updated_at: iso(t.updated_at) }
      end
               })
    sign_out user
  end

  it 'writes the settings, account and insights pages' do
    FileUtils.mkdir_p(fixtures.join('settings'))
    allow(ENV).to receive(:fetch).and_call_original
    allow(ENV).to receive(:fetch).with('JWT_SECRET_KEY').and_return('phoenix-a5-jwt-fixture-secret-not-for-production')

    travel_to now do
      capture('general_en', member(5321), '/settings/general')
      capture('general_supporter_en',
              member(5322, consent: :granted, settings: { 'supporter_email' => 'a5s3-fan@dawarich.test' }),
              '/settings/general', supporter: { supporter: true, platform: 'patreon' })
      capture('general_unverified_en',
              member(5323, consent: :declined,
                           settings: { 'timezone' => 'Berlin', 'supporter_github_username' => 'a5s3-octo',
                                       'digest_emails_enabled' => false, 'news_emails_enabled' => false }),
              '/settings/general')
      capture('general_nosmtp_en', member(5324), '/settings/general', smtp: false)
      capture('general_cloud_en', member(5325), '/settings/general', self_hosted: false)
      capture('general_admin_en', member(5326, admin: true, settings: { 'monthly_digest_emails_enabled' => false }),
              '/settings/general', two_factor: true)

      connected = member(5311, settings: {
                           'immich_url' => 'https://immich.a5s3.test', 'immich_api_key' => 'a5s3-k-immich',
                           'immich_skip_ssl_verification' => true, 'immich_connection_status' => 'ok',
                           'photoprism_url' => 'https://photoprism.a5s3.test', 'photoprism_api_key' => 'a5s3-k-photo',
                           'photoprism_connection_status' => 'failed',
                           'airtrail_url' => 'https://airtrail.a5s3.test', 'airtrail_api_key' => 'a5s3-k-air',
                           'airtrail_last_synced_at' => '2026-09-25T10:15:00+00:00',
                           'teslamate_url' => 'https://tesla.a5s3.test', 'teslamate_username' => 'a5s3-driver',
                           'teslamate_password' => 'a5s3-k-pw', 'teslamate_api_token' => 'a5s3-k-tok',
                           'teslamate_last_synced_at' => '2026-09-24T08:00:00Z', 'teslamate_connection_status' => 'ok'
                         })
      source(53_111, connected, 'https://trek-one.a5s3.test', last_synced_at: now - 1.day)
      source(53_112, connected, 'https://trek-two.a5s3.test', status: :disabled, last_error: 'TREK answered 401',
                                                              created_at: now - 2.days)
      source(53_113, connected, 'https://trek-three.a5s3.test', importing: true, created_at: now - 1.day)
      %w[immich photoprism airtrail teslamate trek].each do |service|
        capture("integrations_#{service}_en", connected, "/settings/integrations?service=#{service}")
      end
      capture('integrations_default_en', connected, '/settings/integrations')
      capture('integrations_unknown_en', connected, '/settings/integrations?service=geocoding')
      admin = member(5312, admin: true, settings: { 'airtrail_url' => 'https://airtrail.a5s3.test',
                                                    'airtrail_last_synced_at' => 'not a time' })
      capture('integrations_admin_en', admin, '/settings/integrations')
      capture('integrations_airtrail_raw_en', admin, '/settings/integrations?service=airtrail')
      capture('integrations_lite_en', member(5313, plan: :lite), '/settings/integrations', self_hosted: false)
      capture('integrations_cloud_oauth_en', member(5314, provider: 'github'), '/settings/integrations',
              self_hosted: false)

      capture('account_en', member(5331), '/users/edit')
      capture('account_oidc_en', member(5332, provider: 'openid_connect'), '/users/edit')
      capture('account_cloud_en', member(5333), '/users/edit', self_hosted: false)
      capture('account_trial_en', member(5334, status: :trial, active_until: now + 5.days), '/users/edit',
              self_hosted: false)
      capture('account_trial_auto_en', member(5335, status: :trial, active_until: now + 5.days, source: :paddle),
              '/users/edit', self_hosted: false)
      capture('account_pending_en', member(5336, status: :pending_payment), '/users/edit', self_hosted: false)
      capture('account_expired_en', member(5337, active_until: now - 2.days), '/users/edit', self_hosted: false)
      capture('account_cloud_oauth_en', member(5338, provider: 'google_oauth2'), '/users/edit', self_hosted: false)

      reader = member(5301)
      stat(53_011, reader, 2024, 3, 38_400, daily_distance: daily(2024, 3, { 5 => 10_000, 6 => 5_400, 7 => 14_000,
                                                                             20 => 9_000 }),
                                           toponyms: [toponym('Germany', 'Berlin'), toponym('Czechia', 'Prague')])
      stat(53_012, reader, 2024, 4, 12_000, daily_distance: daily(2024, 4, { 10 => 12_000 }),
                                           toponyms: [toponym('Germany', 'Berlin')])
      stat(53_013, reader, 2023, 7, 20_000, daily_distance: daily(2023, 7, { 14 => 20_000 }),
                                           toponyms: [toponym('Germany', 'Berlin'), toponym(nil, 'Nowhere'),
                                                      { 'country' => 'Austria', 'cities' => [] }])
      capture('insights_en', reader, '/insights')
      capture('insights_year_en', reader, '/insights?year=2023')
      capture('insights_all_en', reader, '/insights?year=all')
      capture('insights_month_en', reader, '/insights?year=2024&month=3')

      current = member(5302)
      stat(53_021, current, 2026, 9, 6_700,
           daily_distance: { '24' => 1_000, '25' => 2_000, '26' => 3_000, '-1' => 700 },
           toponyms: [toponym('Germany', 'Leipzig')])
      stat(53_022, current, 2026, 8, 900, daily_distance: [[31, 500], [30, 0], [29, 400]])
      capture('insights_current_en', current, '/insights')

      capture('insights_empty_en', member(5303), '/insights?year=2020')

      lite = member(5304, plan: :lite)
      stat(53_041, lite, 2024, 6, 30_000, daily_distance: daily(2024, 6, { 2 => 30_000 }),
                                         toponyms: [toponym('Germany', 'Berlin')])
      stat(53_042, lite, 2025, 10, 8_000, daily_distance: daily(2025, 10, { 3 => 8_000 }),
                                         toponyms: [toponym('Germany', 'Berlin')])
      stat(53_043, lite, 2026, 2, 4_000, daily_distance: daily(2026, 2, { 4 => 4_000 }),
                                        toponyms: [toponym('Czechia', 'Prague')])
      capture('insights_lite_locked_en', lite, '/insights?year=2024', self_hosted: false)
      capture('insights_lite_en', lite, '/insights', self_hosted: false)

      miles = member(5305, settings: { 'maps' => { 'distance_unit' => 'mi' } })
      stat(53_051, miles, 2024, 5, 16_093, daily_distance: daily(2024, 5, { 9 => 16_093 }))
      capture('insights_mi_en', miles, '/insights?year=2024')

      legacy = member(5306)
      stat(53_061, legacy, 2024, 12, 100_000, daily_distance: daily(2024, 12, { 24 => 100_000 }))
      stat(53_062, legacy, 2024, 11, 5_000, daily_distance: daily(2024, 11, { 1 => 5_000 }))
      Stat.where(id: 53_061).update_all(month: 13)
      capture('insights_legacy_en', legacy, '/insights?year=2024')
    end
  end
end
