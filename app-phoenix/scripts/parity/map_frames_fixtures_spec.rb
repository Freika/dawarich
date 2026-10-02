# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Phoenix fixtures: the map frames as Rails renders them', type: :request do
  include ActiveSupport::Testing::TimeHelpers

  let(:dir) { Rails.root.join('app-phoenix/test/fixtures/map_frames') }
  let(:now) { Time.utc(2026, 9, 29, 10, 0, 0) }
  let(:manager_url) { 'https://manager.a6s2-fixture.test' }
  let(:tables) { %w[places areas tags taggings visits place_visits tracks track_segments points stats] }
  let(:accepts) do
    { 'frame' => 'text/html, application/xhtml+xml',
      'stream' => 'text/vnd.turbo-stream.html, text/html, application/xhtml+xml',
      'browser' => 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
      'any' => '*/*',
      'none' => '' }
  end

  around do |example|
    ActionController::Base.allow_forgery_protection = true
    example.run
  ensure
    ActionController::Base.allow_forgery_protection = false
  end

  before do
    allow(ENV).to receive(:fetch).and_call_original
    allow(ENV).to receive(:fetch).with('JWT_SECRET_KEY')
                                 .and_return('phoenix-a6s2-jwt-fixture-secret-not-for-production')
    FileUtils.mkdir_p(dir)
  end

  def reader(id, timezone: 'Europe/Berlin', plan: :pro, redetected: true, **settings)
    user = create(:user, id:, email: "a6s2-#{id}@dawarich.test", changelog_consent: :declined)
    merged = user.settings.merge('onboarding_completed' => true, 'timezone' => timezone)
                 .merge(settings.deep_stringify_keys)
    user.update_columns(settings: merged, plan: User.plans[plan], status: User.statuses[:active],
                        active_until: Time.utc(3026, 1, 1), api_key: "a6s2-k-#{id}",
                        visits_redetected_at: redetected ? now - 10.days : nil)
    user.reload
  end

  def cloud!
    allow(DawarichSettings).to receive(:self_hosted?).and_return(false)
    stub_const('SELF_HOSTED', false)
    stub_const('MANAGER_URL', manager_url)
  end

  def at(day, time, zone = 'Europe/Berlin') = ActiveSupport::TimeZone[zone].parse("#{day} #{time}").utc

  def place!(user, id, name, east: 0.0, north: 0.0, legacy: false)
    lat = (51.3397 + north).round(6)
    lon = (12.3731 + east).round(6)
    Place.insert!({ id:, user_id: user.id, name:, city: 'Leipzig', country: 'Germany', latitude: lat,
                    longitude: lon, lonlat: legacy ? nil : "POINT(#{lon} #{lat})" })
    id
  end

  def tag!(user, id, name, place_id, color: '#aa33cc', icon: nil)
    Tag.insert!({ id:, user_id: user.id, name:, color:, icon: })
    Tagging.insert!({ id:, tag_id: id, taggable_type: 'Place', taggable_id: place_id,
                      created_at: now + id.seconds, updated_at: now })
  end

  def area!(user, id, name)
    Area.insert!({ id:, user_id: user.id, name:, latitude: 51.3406, longitude: 12.3816, radius: 120 })
    id
  end

  def visit!(user, id, from, to, name: "Visit #{id}", status: :confirmed, place: nil, area: nil,
             confidence: nil, deleted: false)
    Visit.insert!({ id:, user_id: user.id, name:, started_at: from, ended_at: to,
                    duration: ((to - from) / 60).round, status: Visit.statuses[status], place_id: place,
                    area_id: area, confidence:, deleted_at: deleted ? now : nil })
    id
  end

  def suggest!(id, visit_id, place_id) = PlaceVisit.insert!({ id:, visit_id:, place_id: })

  def track!(user, id, from, to, mode: :walking, distance: 1500, duration: nil, speed: 5.4, gain: nil, loss: nil)
    Track.insert!({ id:, user_id: user.id, start_at: from, end_at: to, distance:,
                    duration: duration || (to - from).to_i, avg_speed: speed,
                    dominant_mode: Track.dominant_modes[mode], elevation_gain: gain, elevation_loss: loss,
                    original_path: 'LINESTRING(12.3731 51.3397, 12.3811 51.3437, 12.3901 51.3402)' })
    id
  end

  def segment!(id, track_id, mode, distance, duration, confidence: nil, corrected: false)
    TrackSegment.insert!({ id:, track_id:, transportation_mode: TrackSegment.transportation_modes[mode],
                           distance:, duration:, confidence_score: confidence,
                           corrected_at: corrected ? now : nil, start_index: id, end_index: id + 1 })
  end

  def points!(user, first_id, times, visit: nil, country: nil)
    rows = times.each_with_index.map do |time, index|
      { id: first_id + index, user_id: user.id, timestamp: time.to_i, visit_id: visit, country_name: country,
        lonlat: 'POINT(12.3731 51.3397)' }
    end
    Point.insert_all!(rows)
  end

  def owner(table, id)
    { 'taggings' => "taggable_type = 'Place' AND taggable_id IN (SELECT id FROM places WHERE user_id = #{id})",
      'place_visits' => "visit_id IN (SELECT id FROM visits WHERE user_id = #{id})",
      'track_segments' => "track_id IN (SELECT id FROM tracks WHERE user_id = #{id})" }
      .fetch(table, "user_id = #{id}")
  end

  def rows(user)
    tables.to_h do |table|
      sql = "SELECT row_to_json(t)::text FROM #{table} t WHERE #{owner(table, Integer(user.id))} ORDER BY t.id"
      [table, ActiveRecord::Base.connection.select_values(sql).map { |row| JSON.parse(row) }]
    end
  end

  def user_row(user)
    { 'id' => user.id, 'email' => user.email, 'theme' => user.theme, 'settings' => user.settings,
      'admin' => user.admin, 'status' => User.statuses[user.status], 'plan' => User.plans[user.plan],
      'active_until' => user.active_until&.utc&.iso8601(6),
      'subscription_source' => User.subscription_sources[user.subscription_source],
      'changelog_consent' => User.changelog_consents[user.changelog_consent], 'api_key' => user.api_key,
      'visits_redetected_at' => user.visits_redetected_at&.utc&.iso8601(6) }
  end

  def state(user, path, accept)
    { 'path' => path, 'accept' => accepts.fetch(accept), 'now' => now.iso8601, 'status' => response.status,
      'content_type' => response.media_type, 'vary' => response.headers['Vary'],
      'location' => response.headers['Location'],
      'session' => { 'user_return_to' => session[:user_return_to], 'alert' => flash[:alert] },
      'self_hosted' => DawarichSettings.self_hosted?, 'env' => { 'TIME_ZONE' => ENV.fetch('TIME_ZONE', nil) },
      'user' => user && user_row(user), 'rows' => user ? rows(user) : {} }
  end

  def write_json(path, data) = File.write(path, "#{Oj.dump(data, mode: :strict, float_precision: 0, indent: 2)}\n")

  def capture(name, user, path, accept: 'frame', as: user)
    Rails.cache.clear
    reset!
    sign_in as if as
    get path, headers: { 'Accept' => accepts.fetch(accept) }
    body = response.body
                   .gsub(/(name="authenticity_token" value=")[^"]*/, '\1CSRF')
                   .gsub(%r{(/auth/dawarich\?token=)[^&"]+}, '\1REDACTED')
    body = '' if response.status >= 400
    raise "#{name} contains a JWT-shaped value" if body.match?(/eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\./)

    File.write(dir.join("#{name}.html"), body)
    write_json(dir.join("#{name}.json"), state(user, path, accept))
    sign_out as if as
  end

  def feed(day, last = day) = "/map/timeline_feeds?start_at=#{day}T00:00:00&end_at=#{last}T23:59:59"

  it 'writes the self-hosted day feeds' do
    travel_to now do
      rich = reader(7101)
      cafe = place!(rich, 7201, 'Café Kowalski, Karl-Liebknecht-Straße, 10, Leipzig, Sachsen', east: 0.002)
      park = place!(rich, 7202, 'Clara-Zetkin-Park', east: -0.01, north: -0.005)
      bakery = place!(rich, 7203, 'Bäckerei Kleinert', east: 0.003)
      twin = place!(rich, 7204, ' bäckerei kleinert ', east: 0.0031)
      tag!(rich, 7701, 'Coffee', cafe, icon: '☕')
      tag!(rich, 7702, 'Work', cafe, color: nil)
      station = area!(rich, 7801, 'Hauptbahnhof')
      d = '2026-09-27'
      track!(rich, 7401, at(d, '07:10'), at(d, '08:00'), mode: :walking, distance: 2400)
      segment!(7501, 7401, :walking, 1800, 1500, confidence: 0.9)
      segment!(7502, 7401, :cycling, 600, 300, confidence: 0.4)
      visit!(rich, 7301, at(d, '08:05'), at(d, '09:40'), name: '', place: cafe)
      track!(rich, 7402, at(d, '09:45'), at(d, '10:05'), mode: :cycling, distance: 3200, duration: 1200)
      segment!(7503, 7402, :cycling, 3000, 500)
      segment!(7504, 7402, :walking, 200, 100, confidence: 0.2, corrected: true)
      visit!(rich, 7302, at(d, '10:10'), at(d, '11:30'), status: :suggested, place: bakery, confidence: 55)
      suggest!(7901, 7302, twin)
      suggest!(7902, 7302, park)
      track!(rich, 7403, at(d, '11:35'), at(d, '12:00'), mode: :stationary, distance: 150)
      track!(rich, 7404, at(d, '11:40'), at(d, '11:50'), mode: :stationary, distance: 40)
      visit!(rich, 7303, at(d, '13:30'), at(d, '14:10'), status: :suggested, area: station, confidence: 20)
      visit!(rich, 7304, at(d, '15:00'), at(d, '16:00'), name: 'Wohnung')
      visit!(rich, 7305, at(d, '16:30'), at(d, '17:00'), status: :declined)
      visit!(rich, 7306, at(d, '17:30'), at(d, '18:00'), deleted: true)
      points!(rich, 7601, [at(d, '08:10'), at(d, '08:40'), at(d, '09:20')], visit: 7301)
      points!(rich, 7611, [at(d, '10:20'), at(d, '11:00')], visit: 7302)
      capture('feed_rich_en', rich, feed(d))

      night = reader(7102)
      track!(night, 7411, at('2026-09-27', '22:30'), at('2026-09-28', '01:30'), mode: :driving, distance: 60_000,
                                                                             speed: 55.0)
      segment!(7511, 7411, :driving, 58_000, 9000, confidence: 0.95)
      visit!(night, 7311, at('2026-09-28', '00:00'), at('2026-09-28', '23:45'), name: 'Hotel Fürstenhof')
      capture('feed_midnight_en', night, feed('2026-09-27', '2026-09-28'))

      legacy = reader(7103, redetected: false, maps: { 'distance_unit' => 'mi' })
      visit!(legacy, 7321, at(d, '09:00'), at(d, '10:00'), name: 'Zoo Leipzig')
      visit!(legacy, 7322, at(d, '11:00'), at(d, '12:00'), status: :suggested, confidence: 10)
      track!(legacy, 7421, at(d, '12:05'), at(d, '12:35'), mode: :driving, distance: 16_093, speed: 32.2)
      capture('feed_legacy_mi_en', legacy, feed(d))

      wide = reader(7106)
      visit!(wide, 7331, at('2026-09-10', '09:00'), at('2026-09-10', '10:00'))
      capture('feed_range_en', wide, '/map/timeline_feeds?start_at=2026-08-27T00:00:00&end_at=2026-09-28T00:00:00')

      epoch = reader(7107)
      visit!(epoch, 7341, at(d, '09:00'), at(d, '10:00'), name: 'Nikolaikirche')
      capture('feed_epoch_en', epoch,
              "/map/timeline_feeds?start_at=#{at(d, '00:00').to_i}&end_at=#{at(d, '23:59:59').to_i}")

      dst = reader(7108)
      track!(dst, 7451, at('2026-10-24', '23:00'), at('2026-10-25', '04:00'), mode: :train, distance: 180_000)
      capture('feed_dst_en', dst, feed('2026-10-24', '2026-10-25'))

      havana = reader(7109, timezone: 'America/Havana')
      track!(havana, 7461, at('2026-03-07', '22:00', 'America/Havana'), at('2026-03-08', '03:00', 'America/Havana'),
             mode: :bus, distance: 40_000)
      capture('feed_havana_en', havana, feed('2026-03-07', '2026-03-08'))

      tokyo = reader(7110, timezone: 'Asia/Tokyo')
      visit!(tokyo, 7371, Time.utc(2026, 1, 15, 23, 30), Time.utc(2026, 1, 16, 1, 0), name: 'Shibuya Sky')
      capture('feed_tokyo_en', tokyo, feed('2026-01-16'))

      capture('feed_signed_out', nil, feed(d))
    end
  end

  it 'writes the Cloud day feeds' do
    travel_to now do
      cloud!
      empty = reader(7104, plan: :lite)
      capture('feed_empty_lite_en', empty, feed('2026-09-27'))

      window = reader(7105, plan: :lite)
      visit!(window, 7351, at('2025-09-29', '11:00'), at('2025-09-29', '11:30'), name: 'Vor dem Fenster')
      visit!(window, 7352, at('2025-09-29', '13:00'), at('2025-09-29', '13:30'), name: 'Im Fenster')
      capture('feed_window_lite_en', window, feed('2025-09-29'))
    end
  end

  it 'writes the track cards' do
    travel_to now do
      km = reader(7111)
      track!(km, 7481, at('2026-09-27', '07:00'), at('2026-09-27', '08:00'), mode: :cycling, distance: 12_345,
                                                                           speed: 18.47, gain: 120, loss: 95)
      capture('track_km_en', km, '/map/timeline_feeds/7481/track_info')

      mi = reader(7112, maps: { 'distance_unit' => 'mi' })
      track!(mi, 7482, at('2026-09-27', '07:00'), at('2026-09-27', '07:30'), mode: :unknown, distance: 800,
                                                                           speed: 0.0)
      capture('track_mi_en', mi, '/map/timeline_feeds/7482/track_info')

      other = reader(7118)
      track!(other, 7483, at('2026-09-27', '07:00'), at('2026-09-27', '07:30'))
      capture('track_foreign', km, '/map/timeline_feeds/7483/track_info')
      capture('track_signed_out', nil, '/map/timeline_feeds/7481/track_info')
    end
  end

  it 'writes the calendars' do
    travel_to now do
      cal = reader(7113)
      visit!(cal, 7381, at('2026-09-03', '10:00'), at('2026-09-03', '12:00'), name: 'Bibliotheca Albertina')
      visit!(cal, 7382, at('2026-09-10', '10:00'), at('2026-09-10', '11:00'), status: :suggested)
      track!(cal, 7491, at('2026-09-15', '08:00'), at('2026-09-15', '20:00'), mode: :walking, distance: 9000)
      track!(cal, 7492, at('2026-09-20', '23:00'), at('2026-09-21', '01:00'), mode: :driving, distance: 30_000)
      track!(cal, 7493, at('2026-08-31', '22:00'), at('2026-09-01', '02:00'), mode: :train, distance: 90_000)
      track!(cal, 7494, at('2026-10-25', '00:30'), at('2026-10-25', '05:00'), mode: :driving, distance: 50_000)
      points!(cal, 7621, [at('2026-09-25', '12:00')])
      capture('calendar_frame_en', cal, '/map/timeline_feeds/calendar?month=2026-09')
      capture('calendar_stream_en', cal, '/map/timeline_feeds/calendar?month=2026-10', accept: 'stream')
      capture('calendar_any_en', cal, '/map/timeline_feeds/calendar?month=2026-09', accept: 'any')
      capture('calendar_browser_en', cal, '/map/timeline_feeds/calendar?month=2026-09', accept: 'browser')
      capture('calendar_none_en', cal, '/map/timeline_feeds/calendar?month=2026-09', accept: 'none')
      capture('calendar_blank_month_en', cal, '/map/timeline_feeds/calendar?month=')
      capture('calendar_signed_out_stream', nil, '/map/timeline_feeds/calendar?month=2026-09', accept: 'stream')
    end
  end

  it 'writes the Cloud calendar' do
    travel_to now do
      cloud!
      lite = reader(7114, plan: :lite)
      visit!(lite, 7391, at('2025-09-30', '10:00'), at('2025-09-30', '11:00'), name: 'Auerbachs Keller')
      capture('calendar_lite_en', lite, '/map/timeline_feeds/calendar?month=2025-09')
    end
  end

  it 'writes the residency frames' do
    travel_to now do
      pro = reader(7115)
      create(:stat, user: pro, year: 2026, month: 1, distance: 1000)
      day = ->(date) { Time.utc(date.year, date.month, date.day, 12) }
      stays = { 'Germany' => [Date.new(2026, 1, 1)..Date.new(2026, 7, 2)],
                'Czechia' => [Date.new(2026, 7, 10)..Date.new(2026, 7, 14),
                              Date.new(2026, 7, 18)..Date.new(2026, 7, 20)],
                'Poland' => [Date.new(2026, 7, 21)..Date.new(2026, 7, 27)],
                'Austria' => [Date.new(2026, 8, 1)..Date.new(2026, 8, 6)],
                'France' => [Date.new(2026, 8, 10)..Date.new(2026, 8, 14)],
                'Italy' => [Date.new(2026, 8, 15)..Date.new(2026, 8, 18)],
                'Spain' => [Date.new(2026, 8, 20)..Date.new(2026, 8, 22)],
                'Netherlands' => [Date.new(2026, 9, 1)..Date.new(2026, 9, 2)],
                'Atlantis' => [Date.new(2026, 9, 5)..Date.new(2026, 9, 5)] }
      next_id = 80_000
      stays.each do |country, ranges|
        times = ranges.flat_map(&:to_a).map(&day)
        points!(pro, next_id, times, country:)
        next_id += times.size
      end
      capture('residency_pro_en', pro, '/map/residency?year=2026')

      empty = reader(7116)
      capture('residency_empty_en', empty, '/map/residency?year=2025')

      default = reader(7117)
      create(:stat, user: default, year: 2024, month: 5, distance: 1000)
      create(:stat, user: default, year: 2025, month: 5, distance: 1000)
      points!(default, 81_000, [Time.utc(2025, 5, 1, 12), Time.utc(2025, 5, 2, 12)], country: 'Germany')
      capture('residency_default_year_en', default, '/map/residency')

      capture('residency_signed_out', nil, '/map/residency?year=2026')
    end
  end
end
