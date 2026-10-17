# frozen_string_literal: true

require 'rails_helper'
require_relative 'fixture_recording'

RSpec.describe 'Phoenix fixtures: the map page as Rails renders it', type: :request do
  closure_cases = {}
  define_method(:closure_case) { |name, data| closure_cases[name] = data }
  after(:all) do
    selected = closure_cases.sort.to_h.select { |name, _| ['page_'].any? { name.start_with?(_1) } }
    unless selected.empty?
      FixtureRecording.source_verify(Rails.root.join('app-phoenix/test/fixtures/map_frames/a12f3a-m01.json'),
                                     "#{JSON.pretty_generate(selected)}\n")
    end
    selected = closure_cases.sort.to_h.select { |name, _| ['page_'].any? { name.start_with?(_1) } }
    unless selected.empty?
      FixtureRecording.source_verify(Rails.root.join('app-phoenix/test/fixtures/map_frames/a12f3a-m07.json'),
                                     "#{JSON.pretty_generate(selected)}\n")
    end
  end

  include ActiveSupport::Testing::TimeHelpers

  let(:fixtures) { Rails.root.join('app-phoenix/test/fixtures') }
  let(:now) { Time.utc(2026, 9, 29, 10, 0, 0) }
  let(:manager_url) { 'https://manager.a6-fixture.test' }

  def json_dump(value, indent = 0)
    pad = '  ' * indent
    inner = '  ' * (indent + 1)
    case value
    when Float
      value.to_s
    when Hash
      return '{}' if value.empty?

      body = value.map { |k, v| "#{inner}#{k.to_s.to_json}: #{json_dump(v, indent + 1)}" }.join(",\n")
      "{\n#{body}\n#{pad}}"
    when Array
      return '[]' if value.empty?

      body = value.map { |v| "#{inner}#{json_dump(v, indent + 1)}" }.join(",\n")
      "[\n#{body}\n#{pad}]"
    else
      value.to_json
    end
  end

  def write_json(path, data) = File.write(path, "#{json_dump(data)}\n")
  def iso(time) = time&.utc&.iso8601(6)
  def utils = ActionDispatch::Journey::Router::Utils

  around do |example|
    ActionController::Base.allow_forgery_protection = true
    example.run
  ensure
    ActionController::Base.allow_forgery_protection = false
  end

  before do
    allow(ENV).to receive(:fetch).and_call_original
    allow(ENV).to receive(:fetch).with('JWT_SECRET_KEY').and_return('phoenix-a6-jwt-fixture-secret-not-for-production')
    FileUtils.mkdir_p(fixtures.join('map'))
  end

  def reader(id, locale: nil, timezone: 'Europe/Berlin', plan: :pro, **settings)
    user = create(:user, id:, email: "a6-map-#{id}@dawarich.test", changelog_consent: :declined)
    forced = { 'onboarding_completed' => true, 'locale' => locale, 'timezone' => timezone }.compact
    user.update_columns(settings: user.settings.merge(forced).merge(settings.stringify_keys),
                        plan: User.plans[plan], status: User.statuses[:active], active_until: Time.utc(3026, 1, 1),
                        api_key: "a6-k-#{id}")
    user.reload
  end

  def cloud!
    allow(DawarichSettings).to receive(:self_hosted?).and_return(false)
    stub_const('SELF_HOSTED', false)
    stub_const('MANAGER_URL', manager_url)
  end

  def scrub!(doc)
    doc.css('input[name="authenticity_token"]').each { |node| node['value'] = 'CSRF' }
    doc.css('meta[name="csrf-token"]').each { |node| node['content'] = 'CSRF' }
    doc.css('[signed-stream-name]').each { |node| node['signed-stream-name'] = 'SIGNED' }
    doc.traverse do |node|
      next unless node.element?

      node.attribute_nodes.each do |attr|
        attr.value = attr.value.gsub(%r{(/auth/dawarich\?token=)[^&"]+}, '\\1REDACTED')
      end
    end
    html = doc.to_html
    raise 'fixture contains a JWT-shaped value' if html.match?(/eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\./)
    raise 'fixture has no #map-shell' unless doc.at_css('#map-shell')
  end

  def rows(user)
    { tags: user.tags.order(:id).map { |t| t.attributes.slice('id', 'name', 'color', 'icon') },
      places: user.places.order(:id).map do |p|
        { id: p.id, name: p.name, latitude: p.latitude.to_s, longitude: p.longitude.to_s,
          lon: p.lonlat&.x, lat: p.lonlat&.y }
      end,
      imports: user.imports.order(:id).map { |i| { id: i.id, name: i.name, demo: i.demo } },
      points: Point.where(user_id: user.id).order(:id).map do |p|
        { id: p.id, import_id: p.import_id, timestamp: p.timestamp, lon: p.lonlat.x, lat: p.lonlat.y }
      end,
      shared_links: user.shared_links.order(:created_at).map do |s|
        { name: s.name, resource_type: SharedLink.resource_types[s.resource_type], revoked_at: iso(s.revoked_at),
          expires_at: iso(s.expires_at) }
      end,
      posters: user.posters.order(:id).map do |p|
        { id: p.id, name: p.name, status: Poster.statuses[p.status], settings: p.settings,
          created_at: iso(p.created_at) }
      end,
      route_videos: user.route_videos.order(:id).map do |v|
        { id: v.id, name: v.name, status: RouteVideo.statuses[v.status], settings: v.settings,
          expired_at: iso(v.expired_at), created_at: iso(v.created_at), updated_at: iso(v.updated_at) }
      end,
      blobs: ActiveStorage::Blob.order(:id).map do |b|
        b.attributes.slice('id', 'key', 'filename', 'byte_size', 'checksum', 'service_name', 'content_type')
      end,
      attachments: ActiveStorage::Attachment.order(:id).map do |a|
        a.attributes.slice('name', 'record_type', 'record_id', 'blob_id')
      end,
      instance_settings: InstanceSetting.order(:id).map { |s| { key: s.key, value: s.value } } }
  end

  def capture(name, user, path, self_hosted: true)
    Rails.cache.clear
    InstanceSettings::Resolver.reset!
    reset!
    sign_in user
    get path
    expect(response).to have_http_status(:ok)
    doc = Nokogiri::HTML5(response.body)
    title = doc.at_css('title').text
    scrub!(doc)
    File.write(fixtures.join("map/#{name}.html"), doc.to_html.gsub(/[ \t]+\n/, "\n"))
    write_json(fixtures.join("map/#{name}.json"), {
                 path:, params: Rack::Utils.parse_query(URI.parse(path).query.to_s), title:, now: now.iso8601,
      self_hosted:, locale: user.settings['locale'] || 'en', manager_url: self_hosted ? nil : manager_url,
      env: { 'TIME_ZONE' => ENV.fetch('TIME_ZONE', nil) },
      user: { id: user.id, email: user.email, theme: user.theme, settings: user.settings, admin: user.admin,
              status: User.statuses[user.status], plan: User.plans[user.plan], active_until: iso(user.active_until),
              subscription_source: User.subscription_sources[user.subscription_source],
              changelog_consent: User.changelog_consents[user.changelog_consent], api_key: user.api_key },
      **rows(user)
               })
    jobs = enqueued_jobs.map { { 'class' => _1[:job].name, 'args' => _1[:args] } }
    captured = { 'path' => path, 'self_hosted' => self_hosted,
                 'body' => doc.to_html, 'status' => response.status, 'media_type' => response.media_type,
                 'location' => response.location, 'headers' => response.headers.slice('Vary', 'Cache-Control'),
                 'set_cookie' => response.headers['Set-Cookie'].present?, 'flash' => flash.to_hash,
                 'rows' => rows(user), 'jobs' => jobs }
    closure_case("page_#{name}", captured)
    sign_out user
  end

  def tag!(user, id, name, color: nil, icon: nil) = Tag.create!(id:, user:, name:, color:, icon:)

  def place!(user, id, name, lat, lon, legacy: false)
    place = Place.create!(id:, user:, name:, latitude: lat, longitude: lon, lonlat: "POINT(#{lon} #{lat})")
    place.update_columns(lonlat: nil) if legacy
    place
  end

  def import_with_points!(user, id, *timestamps)
    import = user.imports.create!(id:, name: "a6-import-#{id}.gpx", source: :gpx)
    timestamps.each_with_index do |ts, index|
      Point.create!(id: (id * 10) + index, user:, import:, timestamp: ts, lonlat: 'POINT(13.4 52.5)')
    end
    import
  end

  def blob!(id, filename, content_type)
    ActiveStorage::Blob.create!(id:, key: "a6k#{id}", filename:, byte_size: 10,
                                checksum: 'AAAAAAAAAAAAAAAAAAAAAA==', service_name: 'test', content_type:)
  end

  def attach!(record, name, blob)
    ActiveStorage::Attachment.create!(name:, record:, blob:)
  end

  def galleries!(user)
    done = user.posters.create!(id: 6301, name: 'A6 Poster Done', status: :completed, settings: {},
                                created_at: now - 2.days)
    user.posters.create!(id: 6302, name: 'A6 Poster Rendering', status: :processing,
                         settings: { 'progress_phase' => 'drawing_route' }, created_at: now - 1.day)
    user.posters.create!(id: 6303, name: 'A6 Poster Failed', status: :failed, created_at: now - 3.days,
                         settings: { 'error' => 'Out of <memory> & time' })
    attach!(done, 'image', blob!(6401, 'poster 6301.png', 'image/png'))
    attach!(done, 'print_pdf', blob!(6402, 'poster:6301;print.pdf', 'application/pdf'))
    stored = user.route_videos.create!(id: 6501, name: 'A6 Video Stored', status: :stored,
                                       settings: { 'format' => 'portrait', 'speed' => 2 }, created_at: now - 2.days)
    user.route_videos.create!(id: 6502, name: 'A6 Video Expired', status: :expired,
                              settings: { 'format' => 'landscape', 'title' => '<b>Tom & Jerry</b>', 'zoom' => 1.5 },
                              expired_at: Time.utc(2026, 9, 1, 18, 30), created_at: now - 40.days)
    attach!(stored, 'file', blob!(6601, 'trip ü video.mp4', 'video/mp4'))
  end

  def capture_redirects
    rows = []
    [true, false].each do |self_hosted|
      allow(DawarichSettings).to receive(:self_hosted?).and_return(self_hosted)
      %w[/map/v1 /maps/v2 /map/v1.html /maps/v2.html].each do |path|
        ['', '?date=2026-08-01&panel=timeline&name=%C3%BC%26', '?start_at=%C3%28'].each do |query|
          %i[get head].each do |method|
            reset!
            public_send(method, path + query)
            expected = path.start_with?('/map/v1') && query.include?('%C3%28') ? 400 : 301
            expect(response.status).to eq(expected)
            rows << { method: method.to_s.upcase, path: path + query, self_hosted:, status: response.status,
                      location: response.location, media_type: response.media_type, body: response.body,
                      cookie: response.headers['Set-Cookie'].present?, flash: flash.to_hash,
                      cache_control: response.headers['Cache-Control'] }
          end
        end
      end
    end
    FixtureRecording.source_verify(fixtures.join('map_frames/a12f3a-m02.json'), "#{JSON.pretty_generate(rows)}\n")
  end

  it 'reads back the complete malformed UTF-8 map redirect packet after recorder helper changes' do
    travel_to now do
      plain = reader(6101)
      capture('self_hosted_en', plain, '/map/v2?start_at=2026-09-20T00:00&end_at=2026-09-20T23:59')
      capture('map_path_en', plain, '/map')
      capture_map_closure(plain)

      rich = reader(6102, live_map_enabled: false, fog_of_war_mode: 'hexagons',
                        enabled_transportation_modes: %w[walking cycling train], airtrail_url: 'https://air.example.test',
                        immich_url: 'https://immich.example.test', immich_api_key: 'a6-k-immich',
                        maps: { 'distance_unit' => 'km', 'hidden_tile_categories' => ['buildings'],
                                'disabled_poi_groups' => ['shopping'] })
      9.times do |i|
        tag!(rich, 6200 + i, "Tag #{(i + 65).chr}", color: (i.zero? ? nil : '#aa33cc'), icon: (i == 1 ? '🏠' : nil))
      end
      capture('timeline_en', rich, '/map/v2?panel=timeline&date=2026-05-28')

      placer = reader(6103, timezone: 'Asia/Kolkata')
      place = place!(placer, 6150, 'A6 Place', 52.520008, 13.404954)
      import = import_with_points!(placer, 6160, 1_767_225_600, 1_767_400_000)
      capture('place_import_en', placer, "/map/v2?place_id=#{place.id}&import_id=#{import.id}")
      legacy = place!(placer, 6151, 'A6 Legacy Place', 48.1371, 11.5754, legacy: true)
      capture('legacy_place_en', placer, "/map/v2?place_id=#{legacy.id}&panel=timeline")

      cloud!
      lite = reader(6104, plan: :lite, maps: { 'distance_unit' => 'mi', 'hidden_tile_categories' => ['roads'] })
      lite.imports.create!(id: 6170, name: 'demo.json', source: :geojson, demo: true)
      lite.shared_links.create!(name: 'A6 live', resource_type: :live, expires_at: now + 1.day)
      capture('cloud_lite_en', lite, '/map/v2', self_hosted: false)

      pro = reader(6105, immich_url: 'https://immich.example.test', immich_api_key: 'a6-k-immich')
      InstanceSetting.create!(key: 'photon_api_host', value: 'photon.a6-fixture.test')
      galleries!(pro)
      capture('cloud_pro_en', pro, '/map/v2?import_id=999999&panel=timeline', self_hosted: false)
      capture_redirects
    end
  end

  def capture_map_closure(user)
    cases = ['2026-05-28', '2026/05/28', '28 May 2026', '2026-3-29'].map do |date|
      reset!
      sign_in user
      path = "/map/v2?#{{ date:, panel: 'timeline' }.to_query}"
      get path
      expect(response).to have_http_status(:ok)
      { path:, params: { date:, panel: 'timeline' }, expected: window_values(Nokogiri::HTML5(response.body)) }
    end
    write_json(fixtures.join('map_frames/a12f3a-m01.json'), { now: now.iso8601, settings: user.settings,
      env: { 'TIME_ZONE' => ENV.fetch('TIME_ZONE', nil) }, cases: })
    markers = %w[map-shell poster-studio video-studio timeline-calendar-frame timeline-feed-frame]
    write_json(fixtures.join('map_frames/a12f3a-m07.json'), { source: 'app/views/map/maplibre/index.html.erb',
      markers: markers.select { |id| Nokogiri::HTML5(response.body).at_css("##{id}") } })
    redirects = %w[/map/v1 /maps/v2].flat_map do |base|
      ['', '?start_at=2026-08-01T00%3A00%3A00&panel=timeline', '?q=Tom+%26+Jerry&tag[]=a&tag[]=b',
       '.json?x=1'].flat_map do |query|
        %w[get head].map do |method|
          reset!
          path = base + query
          public_send(method, path)
          { method:, path:, status: response.status, location: response.headers['Location'], body: response.body }
        end
      end
    end
    write_json(fixtures.join('map_frames/a12f3a-m02.json'), { cases: redirects })
  end

  def window_cases
    [
      { tz: 'Europe/Berlin', params: {} },
      { tz: 'Europe/Berlin', params: { 'start_at' => '2025-10-15T00:00', 'end_at' => '2025-10-15T23:59' } },
      { tz: 'Europe/Berlin',
        params: { 'start_at' => '2025-10-15T00:00:00+05:00', 'end_at' => '2025-10-16T12:30:45Z' } },
      { tz: 'Europe/Berlin',
        params: { 'start_at' => '2025-10-15T08:00:00.750+0200', 'end_at' => '2025-10-15 18:45' } },
      { tz: 'Europe/Berlin', params: { 'start_at' => '1760486400', 'end_at' => '1760572799' } },
      { tz: 'Europe/Berlin', params: { 'start_at' => '99999999999', 'end_at' => '0' } },
      { tz: 'Europe/Berlin', params: { 'start_at' => '2150-01-01T00:00', 'end_at' => '1969-06-01T00:00' } },
      { tz: 'Europe/Berlin', params: { 'start_at' => '2025-10-15', 'end_at' => '2025-10-15 18:45:30' } },
      { tz: 'Europe/Berlin', params: { 'start_at' => 'garbage', 'end_at' => '2025-13-45T10:00' } },
      { tz: 'Europe/Berlin', params: { 'start_at' => '2000-01-01T00:00', 'end_at' => '2000-01-01T12:00' } },
      { tz: 'Europe/Berlin', params: { 'date' => '2026-05-28', 'panel' => 'timeline' } },
      { tz: 'Europe/Berlin', params: { 'date' => 'today', 'panel' => 'timeline' } },
      { tz: 'Europe/Berlin', params: { 'date' => '2026-3-29' } },
      { tz: 'Europe/Berlin', params: { 'date' => 'not-a-date' } },
      { tz: 'Europe/Berlin',
        params: { 'date' => '2026-05-28', 'start_at' => '2026-05-20T00:00', 'end_at' => '2026-05-20T23:59' } },
      { tz: 'Europe/Berlin', params: { 'date' => '2026-05-28', 'start_at' => '2026-05-20T08:00' } },
      { tz: 'Europe/Berlin', params: { 'start_at' => '2026-03-29T02:30', 'end_at' => '2026-10-25T02:30' } },
      { tz: 'Australia/Lord_Howe',
        params: { 'start_at' => '2026-04-05T01:45', 'end_at' => '2026-10-04T02:15' } },
      { tz: 'Antarctica/Troll',
        params: { 'start_at' => '2026-10-25T01:30', 'end_at' => '2026-10-25T01:45' } },
      { tz: 'Europe/Berlin',
        params: { 'start_at' => '2026-03-31T10:00', 'end_at' => '2026-03-31T11:00', 'import_id' => '7',
                  'panel' => 'layers' } },
      { tz: 'Berlin', params: {} },
      { tz: 'Eastern Time (US & Canada)', params: { 'date' => '2026-11-01' } },
      { tz: 'America/New_York', params: { 'start_at' => '2026-11-01T01:30', 'end_at' => '2026-11-01T23:59' } },
      { tz: 'Pacific/Kiritimati', params: { 'start_at' => '2026-02-28T23:30', 'end_at' => '2026-03-01T00:30' } },
      { tz: nil, params: { 'date' => '2026-05-28' } },
      { tz: '', params: { 'date' => '2026-05-28' } },
      { tz: 'Asia/Kolkata', params: {}, import: :own },
      { tz: 'Asia/Kolkata', params: { 'date' => '2026-01-02' }, import: :own },
      { tz: 'Asia/Kolkata', params: {}, import: :foreign },
      { tz: 'Antarctica/Casey', params: { 'start_at' => '2018-03-11T02:30', 'end_at' => '2023-03-09T01:30' } },
      { tz: 'Antarctica/Vostok', params: { 'start_at' => '2023-12-18T00:30', 'end_at' => '2023-12-18T01:45' } },
      { tz: 'Asia/Pyongyang', params: { 'start_at' => '2015-08-14T23:45', 'end_at' => '2015-08-14T23:30' } },
      { tz: 'Pacific/Norfolk', params: { 'start_at' => '2015-10-04T01:45', 'end_at' => '2026-04-05T02:30' } }
    ]
  end

  def window_values(doc)
    root = doc.at_css('#maps-maplibre-container')
    nav = doc.at_css('[data-controller="map-controls"]')
    hrefs = nav.css('a').map { |a| a['href'] }
    query = ->(href) { Rack::Utils.parse_query(URI.parse(href).query.to_s) }
    pair = ->(href) { query.call(href).values_at('start_at', 'end_at') }
    tips = nav.css('.tooltip[data-tip]').map { |node| node['data-tip'] }
    calendar_frame = doc.at_css('#timeline-calendar-frame')
    { start: root['data-maps--maplibre-start-date-value'], end: root['data-maps--maplibre-end-date-value'],
      iana: root['data-maps--maplibre-timezone-value'], import_id: root['data-maps--maplibre-import-id-value'],
      start_local: nav.at_css('input[name="start_at"]')['value'],
      end_local: nav.at_css('input[name="end_at"]')['value'],
      label: nav.at_css('[data-map-controls-target="mobileLabel"]').text, prev_tip: tips[0], next_tip: tips[3],
      prev: pair.call(hrefs[0]), next: pair.call(hrefs[1]), today: pair.call(hrefs[2]),
      week: pair.call(hrefs[3]), month: pair.call(hrefs[4]),
      share: query.call(hrefs[5]).values_at('start_date', 'end_date'),
      calendar: query.call(calendar_frame['src'])['month'] }
  end

  it 'writes the window corpus' do
    travel_to now do
      other = reader(6190)
      foreign = import_with_points!(other, 6191, 1_700_000_000)
      cases = window_cases.each_with_index.map do |c, index|
        user = reader(6700 + index, timezone: c[:tz])
        user.update_columns(settings: user.settings.except('timezone')) if c[:tz].nil?
        import = { own: -> { import_with_points!(user, 6800 + index, 1_767_225_600, 1_767_400_000) },
                   foreign: -> { foreign } }[c[:import]]&.call
        params = import ? c[:params].merge('import_id' => import.id.to_s) : c[:params]
        reset!
        sign_in user
        get "/map/v2?#{params.to_query}"
        expect(response).to have_http_status(:ok)
        sign_out user
        range = c[:import] == :own ? { min: 1_767_225_600, max: 1_767_400_000 } : nil
        { tz: c[:tz], params:, import: range, expected: window_values(Nokogiri::HTML5(response.body)) }
      end
      write_json(fixtures.join('map_window.json'), { env: { 'TIME_ZONE' => ENV.fetch('TIME_ZONE', nil) },
                                                     now: now.iso8601, cases: })
    end
  end

  def blob_signed(secret, id)
    keys = ActiveSupport::KeyGenerator.new(secret, iterations: 1000)
    ActiveSupport::MessageVerifiers.new { |salt| keys.generate_key(salt) }.rotate_defaults['ActiveStorage']
                                   .generate(id, purpose: :blob_id)
  end

  def stream_signed(secret, user)
    key = ActiveSupport::KeyGenerator.new(secret, iterations: 1000).generate_key('turbo/signed_stream_verifier_key')
    ActiveSupport::MessageVerifier.new(key, digest: 'SHA256', serializer: JSON)
                                  .generate(Turbo::StreamsChannel.send(:stream_name_from, [user, :posters]))
  end

  def blob_path(secret, blob, disposition = nil)
    path = "/rails/active_storage/blobs/redirect/#{utils.escape_segment(blob_signed(secret, blob.id))}/" \
           "#{utils.escape_path(blob.filename.to_param)}"
    disposition ? "#{path}?disposition=#{disposition}" : path
  end

  it 'writes the Rails-signed token corpus' do
    base = Rails.application.secret_key_base
    secret = 'phoenix-a6-message-fixture-secret-not-for-production'
    users = [6901, 6902].map { |id| create(:user, id:, email: "a6-sign-#{id}@dawarich.test") }
    blobs = ['poster 1.png', 'a:b;c/d?.mp4', "  trip ü.mp4\t", 'x%$|<>*"\\.png', 'plain.pdf']
            .each_with_index.map { |name, i| blob!(6_910_000 + (i * 997), name, 'application/octet-stream') }
    helpers = Rails.application.routes.url_helpers

    blobs.each do |blob|
      expect(blob.signed_id).to eq(blob_signed(base, blob.id))
      expect(helpers.rails_blob_path(blob, only_path: true)).to eq(blob_path(base, blob))
      expect(helpers.rails_blob_path(blob, disposition: 'attachment', only_path: true))
        .to eq(blob_path(base, blob, 'attachment'))
    end
    users.each { |user| expect(Turbo::StreamsChannel.signed_stream_name([user, :posters])).to eq(stream_signed(base, user)) }

    write_json(fixtures.join('rails_messages.json'), {
                 secret:,
      blobs: ([1, 62, 999_999_999] + blobs.map(&:id)).map { |id| { id:, signed: blob_signed(secret, id) } },
      streams: users.map { |user| { user_id: user.id, signed: stream_signed(secret, user) } },
      paths: blobs.flat_map do |blob|
        [nil, 'attachment'].map do |d|
          { id: blob.id, filename: blob[:filename], disposition: d, path: blob_path(secret, blob, d) }
        end
      end
               })
  end
end
