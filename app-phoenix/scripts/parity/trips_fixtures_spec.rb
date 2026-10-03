# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Phoenix fixtures: the trips pages as Rails renders them', type: :request do
  include ActiveSupport::Testing::TimeHelpers

  let(:dir) { Rails.root.join('app-phoenix/test/fixtures/trips') }
  let(:now) { Time.utc(2026, 9, 29, 12, 0, 0) }
  let(:secret) { 'phoenix-a2-cookie-fixture-secret-not-for-production' }
  let(:helper) { ApplicationController.helpers }

  around do |example|
    ActionController::Base.allow_forgery_protection = true
    example.run
  ensure
    ActionController::Base.allow_forgery_protection = false
  end

  before { FileUtils.mkdir_p(dir.join('pages')) }

  def write_json(name, data)
    File.write(dir.join(name), "#{Oj.dump(data.deep_stringify_keys, mode: :strict, float_precision: 0, indent: 2)}\n")
  end

  def utc(text) = Time.iso8601(text)

  def user_settings
    {
      9801 => { 'timezone' => 'Europe/Berlin', 'airtrail_url' => ' ' },
      9802 => { 'timezone' => 'America/New_York', 'maps' => { 'distance_unit' => 'mi' },
                'maps_maplibre_style' => 'dark', 'airtrail_url' => 'https://airtrail.example',
                'meters_between_routes' => '750', 'minutes_between_routes' => 90 },
      9803 => { 'timezone' => 'UTC' },
      9804 => { 'timezone' => 'Europe/Berlin' },
      9805 => { 'timezone' => 'Europe/Berlin' },
      9899 => { 'timezone' => 'Europe/Berlin' }
    }
  end

  def loop_path
    [[12.373468123456789, 51.33970012345678], [12.38, 51.345], [12.391234567890123, 51.34987654321098],
     [12.4, 51.34000000000001], [12.373468123456789, 51.33970012345678]]
  end

  def short_path = [[12.3712, 51.3391], [12.3801, 51.3422]]

  def line(lon, lat, count) = (0...count).map { |i| [lon + (i * 0.001), lat + (i * 0.0005)] }

  def trip(id, user_id, name, started, ended, opts = {})
    { id:, user_id:, name:, started_at: started, ended_at: ended, distance: opts[:distance],
      visited_countries: opts.fetch(:countries, []), path: opts[:path], recalculated_offset: opts[:recalculated] }
  end

  def many_trips
    (1..14).map do |n|
      trip(980_500 + n, 9805, format('Many %02d', n), (Time.utc(2024, 1, 1, 8) + n.days).iso8601(6),
           (Time.utc(2024, 1, 1, 18) + n.days).iso8601(6), distance: n.even? ? n * 1000 : nil,
           countries: n.even? ? ['Germany'] : [], path: n.even? ? line(12.3 + (n * 0.01), 51.3, 2) : nil)
    end
  end

  def trips
    [
      trip(980_101, 9801, 'Leipzig loop', '2026-05-09T06:00:00.000000Z', '2026-05-12T20:00:00.000000Z',
           distance: 12_345, countries: ['Germany'], path: loop_path, recalculated: 30),
      trip(980_102, 9801, 'Grenzgang <b>&</b> "Saale"', '2026-01-31T09:00:00.000000Z',
           '2026-02-02T07:00:00.000000Z', distance: 999_500, countries: %w[Germany France],
           path: line(12.35, 51.33, 3), recalculated: 3600),
      trip(980_103, 9801, 'No points', '2025-12-01T08:00:00.000000Z', '2025-12-01T18:00:00.000000Z', distance: 0),
      trip(980_104, 9801, 'Calculating', '2025-11-01T08:00:00.000000Z', '2025-11-02T08:00:00.000001Z',
           countries: {}),
      trip(980_105, 9801, 'Countryless', '2025-10-01T08:00:00.000000Z', '2025-10-01T09:30:00.000000Z',
           distance: 500, path: short_path),
      trip(980_106, 9801, 'Short hop', '2025-09-01T08:00:00.000000Z', '2025-09-01T09:00:00.000000Z',
           distance: 1499, countries: ['Germany'], path: short_path),
      trip(980_201, 9802, 'Auenwald walk', '2026-04-20T13:00:00.000000Z', '2026-04-21T02:30:00.000000Z',
           distance: 16_093, countries: ['United States'], path: line(12.33, 51.35, 4), recalculated: 3600),
      trip(980_301, 9803, 'Midnight run', '2026-06-01T22:00:00.000000Z', '2026-06-03T01:00:00.000000Z',
           distance: 800, countries: ['Germany'], path: line(12.36, 51.32, 2)),
      trip(980_302, 9803, 'Auwald notes', '2026-07-04T08:00:00.000000Z', '2026-07-05T18:00:00.000000Z',
           distance: 2500, countries: ['Germany'], path: short_path),
      *many_trips,
      trip(989_901, 9899, 'Foreign trip', '2026-05-09T06:00:00.000000Z', '2026-05-12T20:00:00.000000Z',
           distance: 1000, countries: ['Germany'], path: loop_path)
    ]
  end

  def point(id, user_id, time, lon, lat, opts = {})
    { id:, user_id:, timestamp: utc(time).to_i, lon:, lat:, tracker_id: opts[:tracker], source_id: opts[:source],
      anomaly: opts[:anomaly] }
  end

  def points
    [
      point(9_810_001, 9801, '2026-05-09T07:00:00Z', 12.37, 51.338, tracker: 'phone'),
      point(9_810_002, 9801, '2026-05-09T07:10:00Z', 12.375, 51.3395, tracker: 'phone'),
      point(9_810_003, 9801, '2026-05-09T07:20:00Z', 12.381, 51.341, tracker: 'phone'),
      point(9_810_004, 9801, '2026-05-09T07:30:00Z', 12.389, 51.344, tracker: 'phone'),
      point(9_810_005, 9801, '2026-05-10T06:00:00Z', 12.3712, 51.3391, tracker: 'phone'),
      point(9_810_006, 9801, '2026-05-10T06:05:00Z', 12.379, 51.342, source: 98_001),
      point(9_810_007, 9801, '2026-05-10T06:15:00Z', 12.376, 51.3405, tracker: 'phone'),
      point(9_810_008, 9801, '2026-05-10T06:20:00Z', 12.383, 51.345, source: 98_001),
      point(9_810_009, 9801, '2026-05-10T06:30:00Z', 12.3801, 51.3422, tracker: 'phone'),
      point(9_810_010, 9801, '2026-05-10T08:00:00Z', 12.39, 51.36, tracker: 'phone', anomaly: true),
      point(9_810_011, 9801, '2026-05-10T09:00:00Z', 12.39, 51.35, tracker: 'phone'),
      point(9_810_012, 9801, '2026-05-10T09:10:00Z', 12.395, 51.353, tracker: 'phone'),
      point(9_810_013, 9801, '2026-05-10T12:00:00Z', 12.4, 51.33, source: 98_001),
      point(9_810_014, 9801, '2026-05-10T12:10:00Z', 12.41, 51.33, source: 98_001),
      point(9_810_015, 9801, '2026-05-10T15:00:00Z', 12.42, 51.325, source: 98_002),
      point(9_810_016, 9801, '2026-05-10T22:30:00Z', 12.37, 51.34, tracker: 'phone'),
      point(9_810_017, 9801, '2026-05-10T22:35:00Z', 12.3701, 51.3403, tracker: 'phone'),
      point(9_810_101, 9801, '2026-02-01T10:00:00Z', 12.35, 51.33, tracker: 'phone'),
      point(9_810_102, 9801, '2026-02-01T11:00:00Z', 12.35, 51.34, tracker: 'phone'),
      point(9_820_001, 9802, '2026-04-20T14:00:00Z', 12.33, 51.35, tracker: 'pixel'),
      point(9_820_002, 9802, '2026-04-20T15:00:00Z', 12.33, 51.37, tracker: 'pixel'),
      point(9_830_001, 9803, '2026-06-01T22:10:00Z', 12.36, 51.32),
      point(9_830_002, 9803, '2026-06-01T22:12:00Z', 12.3601, 51.3201),
      point(9_830_003, 9803, '2026-06-03T00:10:00Z', 12.36, 51.32),
      point(9_830_004, 9803, '2026-06-03T00:40:00Z', 12.36, 51.335),
      point(9_890_001, 9899, '2026-05-09T07:05:00Z', 12.37, 51.338, tracker: 'phone'),
      point(9_890_002, 9899, '2026-05-10T06:10:00Z', 12.379, 51.342, tracker: 'phone')
    ]
  end

  def countries
    [{ name: 'Germany', iso_a2: 'DE', iso_a3: 'DEU' }, { name: 'France', iso_a2: 'FR', iso_a3: 'FRA' },
     { name: 'United States', iso_a2: 'US', iso_a3: 'USA' }]
  end

  def sources = [{ id: 98_001, tracker_id: 'watch' }, { id: 98_002, tracker_id: nil }]

  def notes
    [{ id: 9_811, trip_id: 980_101, user_id: 9801, noted_at: '2026-05-10T12:00:00Z',
       body: "Morgenkaffee <b>am</b> See\nthen the Auensee" },
     { id: 9_812, trip_id: 980_101, user_id: 9801, noted_at: '2026-05-20T12:00:00Z', body: 'Outside the trip' },
     { id: 9_833, trip_id: 980_302, user_id: 9803, noted_at: '2026-07-05T12:00:00Z',
       body: %(Picknick am "Auensee" & 'Rosental') },
     { id: 9_891, trip_id: 989_901, user_id: 9899, noted_at: '2026-05-10T12:00:00Z', body: 'Foreign note' }]
  end

  def described
    '<h1>Leipzig &amp; the Auwald</h1><div>From the <strong>Rosental</strong> <em>along</em> the ' \
      '<del>Elster</del> Pleiße<br>two&nbsp;&nbsp;spaces, "quotes" and 3 &lt; 4 &gt; 2</div>' \
      '<blockquote>Leise rauscht der Fluss</blockquote><ul><li>Rosental<ul><li>Zoo</li></ul></li><li>' \
      '<a href="https://www.leipzig.de/freizeit?x=1&amp;y=2#auwald">Auwald</a></li></ul><ol><li>Auensee</li>' \
      "</ol><pre>12.3712 51.3391\n12.3801 51.3422</pre>"
  end

  def rich_texts = [{ trip_id: 980_302, body: described }]

  def shared_links
    [{ id: 'a8510000-0000-4000-8000-000000000001', resource_type: 0, trip_id: 980_101, user_id: 9801,
       revoked: false, expires_offset: 7.days.to_i },
     { id: 'a8510000-0000-4000-8000-000000000002', resource_type: 0, trip_id: 980_201, user_id: 9802,
       revoked: true, expires_offset: nil },
     { id: 'a8510000-0000-4000-8000-000000000003', resource_type: 0, trip_id: 980_201, user_id: 9802,
       revoked: false, expires_offset: -1.day.to_i },
     { id: 'a8510000-0000-4000-8000-000000000004', resource_type: 1, trip_id: 980_102, user_id: 9801,
       revoked: false, expires_offset: nil },
     { id: 'a8510000-0000-4000-8000-000000000005', resource_type: 0, trip_id: 989_901, user_id: 9899,
       revoked: false, expires_offset: nil }]
  end

  def posters
    [{ id: 9_831, user_id: 9803, name: 'Leipzig poster', status: 0, created_at: '2026-09-20T10:00:00.000000Z' }]
  end

  def route_videos
    [{ id: 9_832, user_id: 9803, name: 'Run video', status: 1, expired_at: '2026-09-01T18:30:00.000000Z',
       settings: { 'format' => 'landscape' }, created_at: '2026-08-20T10:00:00.000000Z' }]
  end

  def create_users!
    user_settings.map do |id, settings|
      user = create(:user, id:, email: "a8-#{id}@dawarich.test", changelog_consent: :declined)
      user.update_columns(settings: user.settings.merge(settings).merge('onboarding_completed' => true),
                          api_key: "a8-k-#{id}")
      user.reload
      { id:, email: user.email, settings: user.settings, api_key: user.api_key }
    end
  end

  def insert!
    Country.insert_all(countries.map { |c| c.merge(created_at: now, updated_at: now) })
    PointSource.insert_all(sources.map { |s| s.merge(digest: "a8s1#{s[:id]}", created_at: now, updated_at: now) })
    Trip.insert_all(trips.map do |t|
      t.slice(:id, :user_id, :name, :distance, :visited_countries)
       .merge(started_at: utc(t[:started_at]), ended_at: utc(t[:ended_at]),
              path: t[:path] && "LINESTRING(#{t[:path].map { |x, y| "#{x} #{y}" }.join(', ')})",
              last_recalculated_at: t[:recalculated_offset] && (now - t[:recalculated_offset]),
              created_at: now, updated_at: now)
    end)
    Point.insert_all(points.map do |p|
      p.slice(:id, :user_id, :timestamp, :tracker_id, :source_id, :anomaly)
       .merge(lonlat: "POINT(#{p[:lon]} #{p[:lat]})", created_at: now, updated_at: now)
    end)
    Note.insert_all(notes.map do |n|
      { id: n[:id], attachable_type: 'Trip', attachable_id: n[:trip_id], user_id: n[:user_id], body: n[:body],
        noted_at: utc(n[:noted_at]), created_at: now, updated_at: now }
    end)
    ActionText::RichText.insert_all(rich_texts.map do |r|
      { record_type: 'Trip', record_id: r[:trip_id], name: 'description', body: r[:body], created_at: now,
        updated_at: now }
    end)
    SharedLink.insert_all(shared_links.map do |l|
      { id: l[:id], name: 'Fixture link', resource_type: SharedLink.resource_types.key(l[:resource_type]),
        resource_id: l[:trip_id], user_id: l[:user_id], revoked_at: l[:revoked] ? now - 1.day : nil,
        expires_at: l[:expires_offset] && (now + l[:expires_offset]), settings: {}, created_at: now, updated_at: now }
    end)
    Poster.insert_all(posters.map do |p|
      p.slice(:id, :user_id, :name).merge(status: Poster.statuses.key(p[:status]), settings: {},
                                          created_at: utc(p[:created_at]), updated_at: utc(p[:created_at]))
    end)
    RouteVideo.insert_all(route_videos.map do |v|
      v.slice(:id, :user_id, :name, :settings).merge(status: RouteVideo.statuses.key(v[:status]),
                                                     expired_at: utc(v[:expired_at]), created_at: utc(v[:created_at]),
                                                     updated_at: utc(v[:created_at]))
    end)
  end

  def pages
    [
      ['index_states', 9801, '/trips'], ['index_ny', 9802, '/trips'], ['index_empty', 9804, '/trips'],
      ['index_many_page1', 9805, '/trips'], ['index_many_page2', 9805, '/trips?page=2'],
      ['index_many_page3', 9805, '/trips?page=3'], ['index_many_page0', 9805, '/trips?page=0'],
      ['index_many_page_negative', 9805, '/trips?page=-1'], ['index_many_page_2abc', 9805, '/trips?page=2abc'],
      ['index_many_page_out', 9805, '/trips?page=4'], ['index_many_extra_param', 9805, '/trips?page=2&view=cards'],
      ['show_leipzig', 9801, '/trips/980101'], ['show_grenzgang', 9801, '/trips/980102'],
      ['show_short_hop', 9801, '/trips/980106'], ['show_ny', 9802, '/trips/980201'],
      ['show_utc', 9803, '/trips/980301'], ['show_described', 9803, '/trips/980302']
    ]
  end

  def capture(name, user_id, path)
    Rails.cache.clear
    sign_in User.find(user_id)
    get path
    expect(response).to have_http_status(:ok)
    doc = Nokogiri::HTML5(response.body)
    doc.css('input[name="authenticity_token"]').each { |node| node['value'] = 'CSRF' }
    File.write(dir.join("pages/#{name}.html"), doc.at_css('body > div.container > div.w-full > div.flex').inner_html)
    sign_out :user
    { name:, user_id:, path:, title: doc.at_css('title').text }
  end

  it 'writes the trips pages and the seed they render' do
    expect(Rails.application.secret_key_base).to eq(secret)
    expect(ENV.values_at('TIME_ZONE', 'PRINT_ORDER_URL')).to eq([nil, nil])

    travel_to now do
      users = create_users!
      insert!
      write_json('pages.json', { pages: pages.map { |name, user_id, path| capture(name, user_id, path) } })
      write_json('seed.json', { users:, countries:, sources:, trips:, points:, notes:, rich_texts:, shared_links:,
                                posters:, route_videos: })
    end
  end

  it 'writes the day-data corpus' do
    travel_to now do
      create_users!
      insert!
      cases = [980_101, 980_102, 980_106, 980_201, 980_301].map do |id|
        trip = Trip.find(id)
        zone = trip.user.timezone_iana
        { trip_id: id, user_id: trip.user_id, from: trip.started_at.to_i, to: trip.ended_at.to_i,
          gap: trip.user.safe_settings.minutes_between_routes * 60, iana: zone,
          windows_json: trip.primary_device_windows.to_json,
          stats: trip.day_stats(zone).sort.map do |day, stat|
            { day: day.iso8601, first: stat[:first_time].strftime('%Y-%m-%dT%H:%M:%S'),
              last: stat[:last_time].strftime('%Y-%m-%dT%H:%M:%S'), distance_m: stat[:distance_m].round(6) }
          end }
      end
      write_json('windows.json', { trips: cases })
    end
  end

  it 'writes the duration and precision corpus' do
    zones = %w[Europe/Berlin America/New_York UTC Asia/Kathmandu]
    spans = [%w[2026-05-09T06:00:00Z 2026-05-12T20:00:00Z], %w[2026-01-31T09:00:00Z 2026-03-02T07:00:00Z],
             %w[2026-01-31T09:00:00Z 2026-02-02T07:00:00Z], %w[2026-04-30T10:00:00Z 2026-05-01T09:00:00Z],
             %w[2025-12-31T23:30:00Z 2026-01-01T00:15:00Z], %w[2026-02-15T12:00:00Z 2027-04-18T16:00:00Z],
             %w[2026-03-20T09:00:00Z 2026-04-10T07:00:00Z], %w[2026-10-20T12:00:00Z 2026-11-18T08:00:00Z],
             %w[2026-10-28T08:00:00Z 2026-11-25T01:30:00Z],
             %w[2026-06-01T10:00:00Z 2026-06-01T10:59:00Z], %w[2026-06-01T10:00:00Z 2026-06-01T10:00:00Z]]
    durations = zones.product(spans).map do |zone, (from, to)|
      text = Time.use_zone(zone) { helper.trip_duration(Trip.new(started_at: utc(from), ended_at: utc(to))) }
      { zone:, started_at: from, ended_at: to, text: }
    end
    values = [1.0, 1.05, 1.15, 1.25, 1.35, 2.675, 9.95, 12.25, 12.35, 99.95, 100.0, 1234.56, 3.14159,
              10.049999999999999, 10.05, 7.000000000000001, 1.0000000000000002, 1.0e21, 123_456_789.25]
    precision = values.map { |value| { value:, text: helper.number_with_precision(value, precision: 1) } }
    write_json('format.json', { durations:, precision: })
  end

  it 'raises for a previous-month wall time inside a DST gap, which Phoenix hands back' do
    trip = Trip.new(started_at: utc('2026-03-30T08:00:00Z'), ended_at: utc('2026-04-29T00:30:00Z'))
    expect { Time.use_zone('Europe/Berlin') { helper.trip_duration(trip) } }.to raise_error(StandardError)
  end

  it 'writes the trip stream-name corpus' do
    expect(Rails.application.secret_key_base).to eq(secret)
    signed = [980_101, 980_301, 1, 123_456_789].map do |id|
      { trip_id: id, signed: Turbo::StreamsChannel.signed_stream_name(Trip.new(id:)) }
    end
    write_json('streams.json', { secret:, trips: signed })
  end
end
