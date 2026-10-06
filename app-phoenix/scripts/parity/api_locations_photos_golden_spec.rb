# frozen_string_literal: true

require 'rails_helper'
require_relative 'fixture_recording'

module ApiLocationsPhotosGoldenOracle
  TABLES = %w[users points].freeze
  IMMICH = 'http://immich.golden.test'
  PHOTOPRISM = 'http://photoprism.golden.test'
  IMMICH_KEY = 'phoenix-a4g3-immich-key'
  ASSET = '3f2a1b4c-5d6e-4f70-8a9b-0c1d2e3f4a5b'
  JPEG = "\xFF\xD8\xFF\xE0\x00\x10phoenix-a4g3\x00\xFF\xD9".b.freeze
  T0 = 1_700_000_000
  ACCEPT = { json: { 'Accept' => 'application/json' }, any: { 'Accept' => '*/*' }, none: {},
             browser: { 'Accept' => 'image/avif,image/webp,*/*;q=0.8' } }.freeze
  HERE = 'lat=52.52&lon=13.405'
  LOC = '/api/v1/locations'
  THUMB = "/api/v1/photos/#{ASSET}/thumbnail".freeze
  OK = { status: 200, calls: 1 }.freeze
  CASES = [
    { name: 'locations_visits', path: "#{LOC}?#{HERE}&name=Caf%C3%A9%20%3CZ%3E&address=A%20%26%20B", seed: :visits },
    { name: 'locations_web_client_headers', path: "#{LOC}?#{HERE}&name=Here&address=", seed: :visits, accept: :any,
      headers: { 'Content-Type' => 'application/json' } },
    { name: 'locations_query_key_no_accept', path: "#{LOC}?#{HERE}", seed: :visits, auth: :query, accept: :none },
    { name: 'locations_limit_one', path: "#{LOC}?#{HERE}&limit=1", seed: :visits },
    { name: 'locations_limit_zero', path: "#{LOC}?#{HERE}&limit=0", seed: :visits },
    { name: 'locations_radius_override', path: "#{LOC}?#{HERE}&radius_override=5", seed: :visits },
    { name: 'locations_dates_berlin', path: "#{LOC}?#{HERE}&date_from=2023-11-15&date_to=2023-11-15", seed: :visits },
    { name: 'locations_dates_new_york', path: "#{LOC}?#{HERE}&date_from=2023-11-15&date_to=2023-11-15",
      seed: :visits, user: { timezone: 'America/New_York' } },
    { name: 'locations_utc_user', path: "#{LOC}?#{HERE}", seed: :visits, user: { timezone: 'UTC' } },
    { name: 'locations_empty', path: "#{LOC}?#{HERE}" },
    { name: 'locations_exponent_negative_zero', path: "#{LOC}?lat=1e-7&lon=-0", seed: :origin },
    { name: 'locations_format_jpg_query', path: "#{LOC}?#{HERE}&format=jpg", seed: :visits },
    { name: 'locations_if_none_match_hit', path: "#{LOC}?#{HERE}", seed: :visits, conditional: true },
    { name: 'locations_missing_lat', path: "#{LOC}?lon=13.405" },
    { name: 'locations_blank_lon', path: "#{LOC}?lat=52.52&lon=%20" },
    { name: 'locations_out_of_range', path: "#{LOC}?lat=90.5&lon=13.405" },
    { name: 'locations_edge_of_range', path: "#{LOC}?lat=90&lon=-180" },
    { name: 'auth_missing_locations', path: "#{LOC}?#{HERE}", auth: :none },
    { name: 'auth_unknown_locations', path: "#{LOC}?#{HERE}", auth: :unknown },
    { name: 'auth_pending_locations', path: "#{LOC}?#{HERE}", user: { status: 'pending_payment' } },
    { name: 'auth_inactive_locations', path: "#{LOC}?#{HERE}", user: { status: 'inactive' } },
    { name: 'auth_expired_locations', path: "#{LOC}?#{HERE}", user: { active_until: Time.utc(2001, 1, 1) } },
    { name: 'replay_locations_loose_coordinate', expect: :rails, path: "#{LOC}?lat=52.52abc&lon=13.405",
      seed: :visits },
    { name: 'replay_locations_negative_limit', expect: :rails, path: "#{LOC}?#{HERE}&limit=-1", seed: :visits },
    { name: 'replay_locations_loose_date', expect: :rails, path: "#{LOC}?#{HERE}&date_from=Nov%2015%202023",
      seed: :visits },
    { name: 'replay_locations_impossible_date', expect: :rails, path: "#{LOC}?#{HERE}&date_from=2023-02-30",
      seed: :visits },
    { name: 'replay_locations_tie', expect: :rails, path: "#{LOC}?#{HERE}", seed: :tie },
    { name: 'replay_locations_zone_case', expect: :rails, path: "#{LOC}?#{HERE}", seed: :visits,
      user: { timezone: 'europe/berlin' } },
    { name: 'replay_locations_client_header', expect: :rails, path: "#{LOC}?#{HERE}",
      headers: { 'X-Dawarich-Client' => 'ios' }, ignore: ['set-cookie'] },
    { name: 'thumbnail_immich', path: "#{THUMB}?source=immich", upstream: OK },
    { name: 'thumbnail_jpg_suffix_browser', path: "#{THUMB}.jpg?source=immich", auth: :query, accept: :browser,
      upstream: OK },
    { name: 'thumbnail_jpg_suffix_any_accept', path: "#{THUMB}.jpg?source=immich", accept: :any, upstream: OK },
    { name: 'thumbnail_format_query_jpg', path: "#{THUMB}?source=immich&format=jpg", accept: :any, upstream: OK },
    { name: 'thumbnail_if_none_match_hit', path: "#{THUMB}?source=immich", conditional: true, upstream: OK },
    { name: 'thumbnail_url_path_prefix', path: "#{THUMB}?source=immich", upstream: OK,
      user: { settings: { 'immich_url' => "#{IMMICH}/immich" } } },
    { name: 'thumbnail_upstream_404', path: "#{THUMB}?source=immich",
      upstream: { status: 404, body: '{"message":"Not found"}', calls: 1 } },
    { name: 'thumbnail_upstream_401', path: "#{THUMB}?source=immich", upstream: { status: 401, body: '{}', calls: 1 } },
    { name: 'thumbnail_upstream_503', path: "#{THUMB}?source=immich",
      upstream: { status: 503, body: 'down', calls: 1 } },
    { name: 'thumbnail_upstream_timeout', path: "#{THUMB}?source=immich", upstream: { fault: :timeout, calls: 2 } },
    { name: 'thumbnail_not_configured', path: "#{THUMB}?source=immich", user: { integrations: :none } },
    { name: 'thumbnail_not_configured_no_source', path: THUMB, user: { integrations: :none } },
    { name: 'thumbnail_unknown_source', path: "#{THUMB}?source=fLICKR" },
    { name: 'thumbnail_unknown_source_escaped', path: "#{THUMB}?source=%3Cb%3E" },
    { name: 'auth_missing_thumbnail_jpg', path: "#{THUMB}.jpg?source=immich", auth: :none },
    { name: 'auth_pending_thumbnail', path: "#{THUMB}?source=immich", user: { status: 'pending_payment' } },
    { name: 'replay_thumbnail_photoprism', expect: :rails, path: "#{THUMB}?source=photoprism", seed: :photoprism,
      user: { integrations: :photoprism } },
    { name: 'replay_thumbnail_photoprism_user_immich_source', expect: :rails, path: "#{THUMB}?source=immich",
      user: { integrations: :photoprism } },
    { name: 'replay_thumbnail_redirect', expect: :rails, path: "#{THUMB}?source=immich",
      upstream: { status: 302, headers: { 'Location' => "#{IMMICH}/elsewhere" }, body: '', calls: 1 } },
    { name: 'replay_thumbnail_403', expect: :rails, path: "#{THUMB}?source=immich",
      upstream: { status: 403, headers: { 'Content-Type' => 'application/json' },
                  body: '{"message":"Missing required permission: asset.view"}', calls: 1 } },
    { name: 'replay_thumbnail_refused', expect: :rails, path: "#{THUMB}?source=immich",
      upstream: { fault: :refused, calls: 0 } },
    { name: 'rails_thumbnail_id_shape', expect: :rails, path: '/api/v1/photos/a.b/thumbnail?source=immich',
      auth: :none },
    { name: 'rails_thumbnail_jpeg_suffix', expect: :rails, path: "#{THUMB}.jpeg?source=immich", auth: :none },
    { name: 'rails_thumbnail_head', expect: :rails, method: :head, path: "#{THUMB}?source=immich", auth: :none },
    { name: 'rails_cloud_thumbnail', expect: :rails, path: "#{THUMB}?source=immich", user: { integrations: :none },
      env: { 'SELF_HOSTED' => 'false' } },
    { name: 'rails_photos_index', expect: :rails, path: '/api/v1/photos?start_date=2024-01-01&end_date=2024-01-02',
      auth: :none },
    { name: 'rails_locations_suggestions', expect: :rails, path: "#{LOC}/suggestions?q=Berlin", auth: :none },
    { name: 'rails_enrich_scan', expect: :rails, method: :post, path: '/api/v1/immich/enrich/scan', auth: :none },
    { name: 'rails_enrich_create', expect: :rails, method: :post, path: '/api/v1/immich/enrich', auth: :none }
  ].freeze
  CLOSURE_CASES = [
    { name: 'closure_photos_photoprism', path: '/api/v1/photos?start_date=2024-01-01&end_date=2024-01-02',
      user: { integrations: :photoprism }, seed: :index_photoprism },
    { name: 'closure_photos_immich', path: '/api/v1/photos?start_date=2024-01-01&end_date=2024-01-02',
      seed: :index_immich },
    { name: 'closure_photos_not_configured', path: '/api/v1/photos', user: { integrations: :none } },
    { name: 'closure_suggestions_empty', path: "#{LOC}/suggestions?q=" },
    { name: 'closure_suggestions_short', path: "#{LOC}/suggestions?q=A" },
    { name: 'closure_suggestions_long', path: "#{LOC}/suggestions?q=#{'a' * 201}" },
    { name: 'closure_thumbnail_dotted_id', path: '/api/v1/photos/a.b/thumbnail?source=immich',
      upstream: OK, asset_id: 'a.b' },
    { name: 'closure_enrich_scan_missing', method: :post, path: '/api/v1/immich/enrich/scan',
      user: { integrations: :none } },
    { name: 'closure_enrich_empty', method: :post, path: '/api/v1/immich/enrich', seed: :enrich_empty }
  ].freeze

  def self.results
    @results ||= []
  end
end

RSpec.describe 'Phoenix fixture: golden locations and photos API requests', type: :request do
  let(:fixture_models) { [User, Point] }
  include FixtureRecording::DeterministicInputs
  after(:all) do
    path = Rails.root.join('app-phoenix/test/fixtures/api_locations_photos/golden.json')
    FileUtils.mkdir_p(path.dirname)
    cases = ApiLocationsPhotosGoldenOracle.results.reject { _1['name'].start_with?('closure_') }
    fixture = { 'time_zone' => ENV.fetch('TIME_ZONE', nil), 'cases' => cases.sort_by { _1['name'] } }
    File.write(path, "#{g3_exact_json(fixture)}\n")
    closure_path = Rails.root.join('app-phoenix/test/fixtures/a12f2b/closure.json')
    FileUtils.mkdir_p(closure_path.dirname)
    closure = closure_path.exist? ? JSON.parse(closure_path.read) : {}
    closure['locations_photos'] = ApiLocationsPhotosGoldenOracle.results
                                                                .select { _1['name'].start_with?('closure_') }
                                                                .sort_by { _1['name'] }
    File.write(closure_path, "#{g3_exact_json(closure.sort.to_h)}\n")
  end

  (ApiLocationsPhotosGoldenOracle::CASES + ApiLocationsPhotosGoldenOracle::CLOSURE_CASES).each do |kase|
    it(kase[:name]) do
      defaults = { method: :get, auth: :bearer, accept: :json, expect: :own, env: {}, seed: :none, user: {} }
      ApiLocationsPhotosGoldenOracle.results << g3_record(kase.reverse_merge(defaults))
    end
  end

  def g3_exact_json(value, depth = 0)
    pad = '  ' * (depth + 1)
    case value
    when Hash
      return '{}' if value.empty?

      entries = value.map { |k, v| "#{pad}#{Oj.dump(k.to_s, mode: :strict)}: #{g3_exact_json(v, depth + 1)}" }
      "{\n#{entries.join(",\n")}\n#{'  ' * depth}}"
    when Array
      return '[]' if value.empty?

      entries = value.map { |v| "#{pad}#{g3_exact_json(v, depth + 1)}" }
      "[\n#{entries.join(",\n")}\n#{'  ' * depth}]"
    when Float
      value.to_s
    else
      Oj.dump(value, mode: :strict)
    end
  end

  def g3_record(kase)
    user = g3_user(kase)
    send("g3_seed_#{kase[:seed]}", user)
    g3_stub(kase)
    allow(DawarichSettings).to receive(:self_hosted?).and_return(false) if kase[:env]['SELF_HOSTED'] == 'false'
    headers = g3_headers(kase, user)
    path = kase[:auth] == :query ? "#{kase[:path]}&api_key=#{user.api_key}" : kase[:path]
    g3_conditional(path, headers) if kase[:conditional]
    setup = ApiLocationsPhotosGoldenOracle::TABLES.map do |table|
      rows = ActiveRecord::Base.connection.select_values("SELECT row_to_json(t)::text FROM #{table} t ORDER BY id")
      [table, rows.map { JSON.parse(_1) }]
    end

    send(kase[:method], path, headers: headers)

    { 'name' => kase[:name], 'expect' => kase[:expect].to_s, 'ignore' => kase[:ignore] || [], 'env' => kase[:env],
      'setup' => setup, 'upstream' => g3_upstream(kase),
      'request' => { 'method' => kase[:method].to_s.upcase, 'target' => path, 'headers' => headers.to_a },
      'response' => g3_response }
  end

  def g3_response
    headers = response.headers.to_h.transform_keys(&:downcase).except('date', 'content-length')
    body = if response.media_type.to_s.start_with?('image/')
             { 'body_base64' => Base64.strict_encode64(response.body) }
           else
             { 'body' => response.body }
           end
    { 'status' => response.status, 'headers' => headers }.merge(body)
  end

  def g3_user(kase)
    attrs = { status: 'active', active_until: nil, timezone: 'Europe/Berlin', integrations: :immich, settings: {} }
            .merge(kase[:user])
    user = create(:user)
    settings = user.settings.merge('timezone' => attrs[:timezone]).merge(g3_integration(attrs[:integrations]))
                   .merge(attrs[:settings])
    user.update_columns(api_key: "phoenix-a4g3-golden-key-#{kase[:name]}", status: User.statuses.fetch(attrs[:status]),
                        active_until: attrs[:active_until], settings:)
    user
  end

  def g3_integration(kind)
    oracle = ApiLocationsPhotosGoldenOracle
    { immich: { 'immich_url' => oracle::IMMICH, 'immich_api_key' => oracle::IMMICH_KEY },
      photoprism: { 'photoprism_url' => oracle::PHOTOPRISM, 'photoprism_api_key' => 'phoenix-a4g3-photoprism-key' },
      none: {} }.fetch(kind)
  end

  def g3_headers(kase, user)
    headers = { 'Host' => 'localhost' }.merge(ApiLocationsPhotosGoldenOracle::ACCEPT.fetch(kase[:accept]))
                                       .merge(kase[:headers] || {})
    headers['Authorization'] = "Bearer #{user.api_key}" if kase[:auth] == :bearer
    headers['Authorization'] = 'Bearer phoenix-a4g3-golden-unknown' if kase[:auth] == :unknown
    headers
  end

  def g3_conditional(path, headers)
    get path, headers: headers
    headers['If-None-Match'] = response.headers['ETag']
  end

  def g3_upstream_url(kase)
    base = kase.dig(:user, :settings, 'immich_url') || ApiLocationsPhotosGoldenOracle::IMMICH
    "#{base}/api/assets/#{kase.fetch(:asset_id, ApiLocationsPhotosGoldenOracle::ASSET)}/thumbnail?size=preview"
  end

  def g3_stub(kase)
    if kase[:name] == 'replay_thumbnail_photoprism_user_immich_source'
      stub_request(:get, %r{\Ahttp:///api/assets/#{ApiLocationsPhotosGoldenOracle::ASSET}/thumbnail\z})
        .to_raise(SocketError)
      return
    end

    up = kase[:upstream] or return
    oracle = ApiLocationsPhotosGoldenOracle
    stub = stub_request(:get, g3_upstream_url(kase))
           .with(headers: { 'X-Api-Key' => oracle::IMMICH_KEY, 'Accept' => 'application/octet-stream' })
    case up[:fault]
    when :timeout then stub.to_timeout
    when :refused then stub.to_raise(Errno::ECONNREFUSED)
    else stub.to_return(status: up[:status], headers: up[:headers] || {}, body: up.fetch(:body, oracle::JPEG))
    end
    stub_request(:get, "#{oracle::IMMICH}/elsewhere").to_return(status: 200, body: oracle::JPEG) if up[:status] == 302
  end

  def g3_upstream(kase)
    up = kase[:upstream] or return nil
    { 'path' => URI(g3_upstream_url(kase)).request_uri, 'api_key' => ApiLocationsPhotosGoldenOracle::IMMICH_KEY,
      'status' => up[:status], 'headers' => (up[:headers] || {}).to_a, 'fault' => up[:fault]&.to_s,
      'body_base64' => Base64.strict_encode64(up.fetch(:body, ApiLocationsPhotosGoldenOracle::JPEG)),
      'calls' => up.fetch(:calls) }
  end

  def g3_point(user, lat, lon, timestamp, **attrs)
    point = create(:point, user:, latitude: lat, longitude: lon, timestamp:, city: attrs[:city],
                           accuracy: attrs.fetch(:accuracy, 10), altitude: attrs.fetch(:altitude, 30))
    point.update_columns(country: attrs[:country], timestamp: attrs.fetch(:stored_timestamp, timestamp))
  end

  def g3_seed_index_photoprism(_user)
    photo = { 'Hash' => 'a.b', 'Type' => 'image', 'Lat' => 52.52, 'Lng' => 13.405,
              'TakenAt' => '2024-01-01T12:00:00Z', 'TakenAtLocal' => '2024-01-01T13:00:00Z',
              'OriginalName' => 'synthetic.jpg', 'Portrait' => true }
    stub_request(:get, %r{http://photoprism.golden.test/api/v1/photos})
      .to_return(body: [photo].to_json, headers: { 'X-Preview-Token' => 'synthetic-preview',
                                'Content-Type' => 'application/json' })
      .then.to_return(body: '[]', headers: { 'X-Preview-Token' => 'synthetic-preview',
                                'Content-Type' => 'application/json' })
  end

  def g3_seed_index_immich(_user)
    photo = { 'id' => 'asset.one', 'type' => 'IMAGE', 'fileCreatedAt' => '2024-01-01T12:00:00Z',
              'localDateTime' => '2024-01-01T13:00:00', 'originalFileName' => 'synthetic.jpg',
              'exifInfo' => { 'latitude' => 52.52, 'longitude' => 13.405, 'orientation' => '6' } }
    stub_request(:post, 'http://immich.golden.test/api/search/metadata')
      .to_return(body: { assets: { items: [photo] } }.to_json, headers: { 'Content-Type' => 'application/json' })
      .then.to_return(body: { assets: { items: [] } }.to_json, headers: { 'Content-Type' => 'application/json' })
  end

  def g3_seed_enrich_empty(_user); end

  def g3_seed_none(_user); end

  def g3_seed_visits(user)
    t0 = ApiLocationsPhotosGoldenOracle::T0
    g3_point(user, 52.52001, 13.40502, t0, accuracy: 20, altitude: 30, city: 'Berlin', country: 'Germany')
    g3_point(user, 52.52003, 13.40499, t0 + 600, accuracy: 5, altitude: 42, city: 'Berlin', country: 'Germany')
    g3_point(user, 52.51998, 13.40505, t0 + 1200, accuracy: nil, altitude: nil)
    g3_point(user, 52.52010, 13.40510, t0 + 7200, accuracy: nil, altitude: 35)
    [0, 1800, 3600, 3900].each_with_index do |offset, i|
      g3_point(user, 52.5202 + (i * 0.00001), 13.4052, t0 + 86_400 + offset, accuracy: 15, altitude: 30 + i)
    end
    [0, 1800, 3600].each_with_index do |offset, i|
      g3_point(user, 52.5195 - (i * 0.00001), 13.4049, t0 + 172_800 + offset, accuracy: 8, altitude: 50)
    end
    g3_point(user, 52.52005, 13.40501, 1, stored_timestamp: nil)
    g3_point(user, 52.5300, 13.4050, t0 + 300)
    other = create(:user)
    other.update_columns(api_key: 'phoenix-a4g3-golden-other')
    g3_point(other, 52.52001, 13.40502, t0 + 60)
  end

  def g3_seed_origin(user) = g3_point(user, 0.0001, 0.0001, ApiLocationsPhotosGoldenOracle::T0)

  def g3_seed_tie(user)
    t0 = ApiLocationsPhotosGoldenOracle::T0
    g3_point(user, 52.52001, 13.40502, t0, accuracy: 5)
    g3_point(user, 52.52002, 13.40503, t0, accuracy: 5)
  end

  def g3_seed_photoprism(user)
    oracle = ApiLocationsPhotosGoldenOracle
    Rails.cache.write("#{Photoprism::CachePreviewToken::TOKEN_CACHE_KEY}_#{user.id}", 'phoenix-a4g3-preview-token')
    stub_request(:get, "#{oracle::PHOTOPRISM}/api/v1/t/#{oracle::ASSET}/phoenix-a4g3-preview-token/tile_500")
      .to_return(status: 200, body: oracle::JPEG)
  end
end
