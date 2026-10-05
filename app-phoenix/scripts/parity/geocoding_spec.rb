# frozen_string_literal: true

require 'rails_helper'
require_relative 'wave5b_fixture_support'
require_relative 'geocoding_fixture_determinism'

RSpec.describe 'Phoenix fixture: Rails reverse geocoding' do
  include Wave5bFixtureSupport
  include GeocodingFixtureDeterminism::Oracle

  let!(:http) { record_http! }
  let!(:results) { capture_results! }
  let!(:effects) { capture_point_effects! }

  before do
    use_real_geocoding_lookups
    allow(Geocoding::RateLimiter).to receive(:sleep)
    allow(DawarichSettings).to receive(:store_geodata?).and_call_original
    Sidekiq.redis { |redis| redis.call('DEL', Stats::GeocodedDays::PENDING_KEY) }
  end

  def capture_results!
    captured = []
    allow(Geocoding::Search).to receive(:call).and_wrap_original do |original, **kwargs|
      original.call(**kwargs).tap { |found| captured.concat(found.map { |result| result_dump(result.data) }) }
    end
    captured
  end

  def capture_point_effects!
    kinds = []
    allow(Points::TileEpoch).to receive(:bump).and_wrap_original do |original, user_id, timestamps:|
      kinds << { 'kind' => 'points.tile_epoch', 'payload' => { 'user_id' => user_id, 'timestamps' => timestamps } }
      original.call(user_id, timestamps:)
    end
    kinds
  end

  def point_effects
    days = Sidekiq.redis { |redis| redis.call('ZRANGE', Stats::GeocodedDays::PENDING_KEY, 0, -1) }
    { 'kinds' => effects, 'geocoded_days' => days }
  end

  def result_dump(data)
    { 'data' => data, 'normalized' => Geocoding::ResultNormalizer.from_data(data).deep_stringify_keys,
      'place_normalized' => ReverseGeocoding::Places::FetchData.allocate.send(:normalize_geocoder_data, data) }
  end

  def config_dump(config = Geocoding::Config.resolved_config)
    { 'enabled' => config.enabled?, 'source' => config.source.to_s, 'provider' => config.provider&.to_s,
      'host' => config.host, 'api_key' => config.api_key, 'use_https' => config.use_https, 'rps' => config.rps,
      'store_geodata' => DawarichSettings.store_geodata? }
  end

  def point_row(point)
    row = rows(<<~SQL.squish, point.id).first
      SELECT row_to_json(x)::text FROM (
        SELECT id, user_id, ST_AsText(lonlat) AS lonlat_wkt, "timestamp", city, country_name, country_id,
               geodata::text AS geodata, reverse_geocoded_at::text AS reverse_geocoded_at, lock_version
        FROM points WHERE id = ?
      ) x
    SQL
    row.merge('reverse_geocoded_at' => clock_state(row['reverse_geocoded_at']))
  end

  def country_row(country)
    rows(<<~SQL.squish, country.id).first
      SELECT row_to_json(x)::text FROM (
        SELECT id, name, iso_a2, iso_a3, ST_AsText(geom) AS geom_wkt FROM countries WHERE id = ?
      ) x
    SQL
  end

  def photon_feature(lat, lon, **properties)
    { type: 'Feature',
      properties: { city: 'Leipzig', country: 'Germany', countrycode: 'DE', name: 'Testplatz', osm_id: 42,
                    osm_type: 'N', osm_key: 'amenity', osm_value: 'cafe' }.merge(properties),
      geometry: { type: 'Point', coordinates: [lon, lat] } }
  end

  def photon_body(lat, lon, **properties)
    { type: 'FeatureCollection', features: [photon_feature(lat, lon, **properties)] }.to_json
  end

  def stub_at(url_pattern, lat, response)
    stub = stub_request(:get, url_pattern).with(query: hash_including('lat' => lat.to_s))
    response == :timeout ? stub.to_timeout : stub.to_return(response)
  end

  def create_points(user, count, geocoded: false)
    Array.new(count) do |i|
      attributes = { user:, lonlat: leipzig(i * 0.0003, i * 0.0009), timestamp: base_ts + (i * 600) }
      attributes.merge!(geocoded ? { city: 'Leipzig', country_name: 'Germany', reverse_geocoded_at: Time.current } : {})
      create(:point, **attributes)
    end
  end

  def fetch_points(calls)
    clear_enqueued_jobs
    calls.map do |point, force|
      before = http.size
      ReverseGeocoding::Points::FetchData.new(point.id, force:).call
      { 'point_id' => point.id, 'force' => force, 'requests' => http.size - before }
    end
  end

  def point_fixture(name, user, points, calls, extra: {}, input: {})
    before_rows = points.map { |point| point_row(point) }
    config = config_dump
    call_log = fetch_points(calls)
    fixture = {
      'input' => { 'users' => [user_row(user)], 'points' => before_rows,
                   'instance_settings' => instance_setting_rows }.merge(input),
      'config' => config, 'calls' => call_log, 'requests' => http, 'cache' => geocoder_cache, 'results' => results,
      'expected' => { 'points' => points.map { |point| point_row(point) }, 'effects' => point_effects }
    }
    write_fixture('geocoding', name, fixture.merge(extra))
  end

  def place_fixture(name, user, place)
    before_rows = places_for(user)
    config = config_dump
    error = nil
    begin
      ReverseGeocoding::Places::FetchData.new(place.id).call
    rescue StandardError => e
      error = e.class.name
    end
    fixture = {
      'input' => { 'users' => [user_row(user)], 'places' => before_rows, 'instance_settings' => instance_setting_rows },
      'config' => config, 'place_id' => place.id, 'requests' => http, 'cache' => geocoder_cache,
      'results' => results, 'expected' => { 'raised' => error, 'places' => places_for(user) }
    }
    write_fixture('geocoding', name, fixture)
  end

  def selfhosted_photon(**extra)
    configure_instance_geocoding(photon_api_host: 'photon.selfhosted.example.test', photon_api_use_https: true, **extra)
  end

  def selfhosted_url = %r{https://photon\.selfhosted\.example\.test/reverse}

  it 'reverse-geocodes through Photon (Komoot) over forced HTTPS at the locked 1 rps, and writes an empty result',
     fixture: :photon_komoot do
    user = create(:user, email: 'w5b-photon-komoot@example.test')
    configure_instance_geocoding(photon_api_host: 'photon.komoot.io', reverse_geocoding_rps: '40')
    ok, empty = create_points(user, 2)
    url = %r{https://photon\.komoot\.io/reverse}
    stub_at(url, leipzig_lat(0), json_response(photon_body(leipzig_lat(0), leipzig_lon(0))))
    stub_at(url, leipzig_lat(0.0003), json_response({ type: 'FeatureCollection', features: [] }))
    point_fixture('photon_komoot', user, [ok, empty], [[ok, false], [empty, false]])
  end

  it "sends the self-hosted Photon's X-Api-Key header over HTTP", fixture: :photon_selfhosted_key do
    user = create(:user, email: 'w5b-photon-selfhosted-key@example.test')
    configure_instance_geocoding(photon_api_host: 'photon.selfhosted.example.test', photon_api_use_https: false,
                                 photon_api_key: 'w5b-k-01')
    point, = create_points(user, 1)
    stub_at(%r{http://photon\.selfhosted\.example\.test/reverse}, leipzig_lat(0),
            json_response(photon_body(leipzig_lat(0), leipzig_lon(0))))
    point_fixture('photon_selfhosted_key', user, [point], [[point, false]])
  end

  it "resolves ChibiGeo's proxy path host, clamps its rate and digests its rate-limit bucket per key",
     fixture: :photon_chibigeo do
    user = create(:user, email: 'w5b-photon-chibigeo@example.test')
    configure_instance_geocoding(photon_api_host: 'app.chibigeo.com/v1/photon', photon_api_key: 'w5b-k-02',
                                 reverse_geocoding_rps: '40')
    point, = create_points(user, 1)
    stub_at(%r{https://app\.chibigeo\.com/v1/photon/reverse}, leipzig_lat(0),
            json_response(photon_body(leipzig_lat(0), leipzig_lon(0))))
    config = Geocoding::Config.resolved_config
    point_fixture('photon_chibigeo', user, [point], [[point, false]],
                  extra: { 'rate_limit' => { 'chibigeo' => Geocoding::Providers.chibigeo?(config.provider, config.host),
                                             'key' => Geocoding::RateLimiter.key_for(config) } })
  end

  it 'puts apiKey in the Geoapify cache key, upcases the country code, and records an HTTP 500', fixture: :geoapify do
    user = create(:user, email: 'w5b-geoapify@example.test')
    configure_instance_geocoding(geoapify_api_key: 'w5b-k-03')
    ok, failing = create_points(user, 2)
    body = { type: 'FeatureCollection',
             features: [{ type: 'Feature',
                          properties: { city: 'Leipzig', country: 'Germany', country_code: 'de', name: 'Testplatz',
                                        lon: leipzig_lon(0), lat: leipzig_lat(0) },
                          geometry: { type: 'Point', coordinates: [leipzig_lon(0), leipzig_lat(0)] } }] }
    url = %r{https://api\.geoapify\.com/v1/geocode/reverse}
    stub_at(url, leipzig_lat(0), json_response(body))
    stub_at(url, leipzig_lat(0.0003), { status: 500, body: '', headers: {} })
    point_fixture('geoapify', user, [ok, failing], [[ok, false], [failing, false]])
  end

  it 'maps a flat Nominatim town onto city, lowercases the code, and records a bandwidth-limit error',
     fixture: :nominatim do
    user = create(:user, email: 'w5b-nominatim@example.test')
    configure_instance_geocoding(nominatim_api_host: 'nominatim.selfhosted.example.test',
                                 nominatim_api_use_https: false)
    ok, failing = create_points(user, 2)
    body = { display_name: 'Testplatz, Leipzig, Germany', lat: leipzig_lat(0).to_s, lon: leipzig_lon(0).to_s,
             address: { town: 'Leipzig', country: 'Germany', country_code: 'de' } }
    url = %r{http://nominatim\.selfhosted\.example\.test/reverse}
    stub_at(url, leipzig_lat(0), json_response(body))
    stub_at(url, leipzig_lat(0.0003), json_response({ error: 'Bandwidth limit exceeded' }))
    point_fixture('nominatim', user, [ok, failing], [[ok, false], [failing, false]])
  end

  it 'takes the first LocationIQ array result and records an invalid-key error', fixture: :locationiq do
    user = create(:user, email: 'w5b-locationiq@example.test')
    configure_instance_geocoding(locationiq_api_key: 'w5b-k-04')
    ok, failing = create_points(user, 2)
    body = [{ display_name: 'Testplatz, Leipzig, Germany', lat: leipzig_lat(0).to_s, lon: leipzig_lon(0).to_s,
              address: { city: 'Leipzig', country: 'Germany', country_code: 'de' } }]
    url = %r{https://us1\.locationiq\.com/v1/reverse}
    stub_at(url, leipzig_lat(0), json_response(body))
    stub_at(url, leipzig_lat(0.0003), json_response({ error: 'Invalid key' }))
    point_fixture('locationiq', user, [ok, failing], [[ok, false], [failing, false]])
  end

  it 'stores an empty geodata but the identity fields when the stored store_geodata is false',
     fixture: :store_geodata_false do
    user = create(:user, email: 'w5b-store-geodata-false@example.test')
    selfhosted_photon(store_geodata: false)
    point, = create_points(user, 1)
    stub_at(selfhosted_url, leipzig_lat(0), json_response(photon_body(leipzig_lat(0), leipzig_lon(0))))
    point_fixture('store_geodata_false', user, [point], [[point, false]])
  end

  it 'resolves a country name alias and drops a name match whose code disagrees',
     fixture: :country_alias_and_mismatch do
    user = create(:user, email: 'w5b-country-alias@example.test')
    selfhosted_photon
    country = create(:country, name: 'United States of America', iso_a2: 'US', iso_a3: 'USA',
                               geom: 'MULTIPOLYGON (((12.3 51.3, 12.3 51.4, 12.45 51.4, 12.45 51.3, 12.3 51.3)))')
    alias_point, mismatch_point = create_points(user, 2)
    stub_at(selfhosted_url, leipzig_lat(0),
            json_response(photon_body(leipzig_lat(0), leipzig_lon(0), country: 'United States', countrycode: 'US')))
    stub_at(selfhosted_url, leipzig_lat(0.0003),
            json_response(photon_body(leipzig_lat(0.0003), leipzig_lon(0.0009),
                                      country: 'United States of America', countrycode: 'ZZ')))
    point_fixture('country_alias_and_mismatch', user, [alias_point, mismatch_point],
                  [[alias_point, false], [mismatch_point, false]], input: { 'countries' => [country_row(country)] })
  end

  it 'skips an already geocoded point unless forced, and a forced unchanged city marks no day',
     fixture: :point_force_and_rerun do
    user = create(:user, email: 'w5b-point-force@example.test')
    selfhosted_photon
    point, = create_points(user, 1, geocoded: true)
    stub_at(selfhosted_url, leipzig_lat(0), json_response(photon_body(leipzig_lat(0), leipzig_lon(0))))
    point_fixture('point_force_and_rerun', user, [point], [[point, false], [point, true]])
  end

  it 'runs the point job per point, releasing each dedupe key unless forced, through a timeout',
     fixture: :point_batch do
    user = create(:user, email: 'w5b-point-batch@example.test')
    selfhosted_photon
    points = create_points(user, 5)
    points.each_with_index do |_point, i|
      response = i == 3 ? :timeout : json_response(photon_body(leipzig_lat(i * 0.0003), leipzig_lon(i * 0.0009)))
      stub_at(selfhosted_url, leipzig_lat(i * 0.0003), response)
    end
    before_rows = points.map { |point| point_row(point) }
    keys_before = dedupe_keys(points)
    clear_enqueued_jobs
    calls = points.each_with_index.map do |point, i|
      ReverseGeocodingJob.perform_now('Point', point.id, force: i == 4)
      { 'point_id' => point.id, 'force' => i == 4 }
    end
    fixture = {
      'input' => { 'users' => [user_row(user)], 'points' => before_rows, 'instance_settings' => instance_setting_rows },
      'config' => config_dump, 'calls' => calls, 'requests' => http, 'cache' => geocoder_cache, 'results' => results,
      'dedupe_keys' => { 'before' => keys_before, 'after' => dedupe_keys(points) },
      'expected' => { 'points' => points.map { |point| point_row(point) }, 'effects' => point_effects }
    }
    write_fixture('geocoding', 'point_batch', fixture)
  end

  def dedupe_keys(points)
    points.to_h do |point|
      [point.id.to_s, Sidekiq.redis { |redis| redis.call('EXISTS', Point.geocode_dedup_key(point.id)) } == 1]
    end
  end

  it 'releases the dedupe key without a lookup when geocoding is disabled', fixture: :point_job_disabled do
    user = create(:user, email: 'w5b-point-disabled@example.test')
    point, = create_points(user, 1)
    Sidekiq.redis { |redis| redis.call('SET', Point.geocode_dedup_key(point.id), '1', 'EX', 86_400) }
    before_row = point_row(point)
    keys_before = dedupe_keys([point])
    clear_enqueued_jobs
    ReverseGeocodingJob.perform_now('Point', point.id)
    fixture = {
      'input' => { 'users' => [user_row(user)], 'points' => [before_row],
                   'instance_settings' => instance_setting_rows },
      'config' => config_dump, 'calls' => [{ 'point_id' => point.id, 'force' => false }], 'requests' => http,
      'dedupe_keys' => { 'before' => keys_before, 'after' => dedupe_keys([point]) },
      'expected' => { 'points' => [point_row(point)], 'effects' => point_effects }
    }
    write_fixture('geocoding', 'point_job_disabled', fixture)
  end

  it 'folds an existing, a repeated and a new osm_id sibling into places', fixture: :place_siblings do
    user = create(:user, email: 'w5b-place-siblings@example.test')
    selfhosted_photon
    create(:place, user:, name: 'Old Name', latitude: leipzig_lat(0), longitude: leipzig_lon(0), source: :photon,
                   geodata: { 'properties' => { 'osm_id' => 100 } })
    place = create(:place, user:, name: 'Suggested place', latitude: leipzig_lat(0), longitude: leipzig_lon(0),
                           source: :manual)
    body = { type: 'FeatureCollection', features: [
      photon_feature(leipzig_lat(0), leipzig_lon(0), name: 'Self Update', osm_id: 999),
      photon_feature(leipzig_lat(0.00005), leipzig_lon(-0.00005), name: 'Existing Sibling', osm_id: 100,
                                                                   osm_value: 'bakery'),
      photon_feature(leipzig_lat(0.0001), leipzig_lon(0.0001), name: 'Duplicate', osm_id: 200, osm_value: 'bar'),
      photon_feature(leipzig_lat(0.0001), leipzig_lon(0.0001), name: 'Duplicate', osm_id: 200, osm_value: 'bar'),
      photon_feature(leipzig_lat(0.0002), leipzig_lon(0.0002), name: 'Brand New', osm_id: 300, osm_value: 'shop')
    ] }
    stub_at(selfhosted_url, leipzig_lat(0), json_response(body))
    place_fixture('place_siblings', user, place)
  end

  it "keeps a name-locked place's name and source through reverse geocoding", fixture: :place_name_locked do
    user = create(:user, email: 'w5b-place-name-locked@example.test')
    selfhosted_photon
    place = create(:place, user:, name: 'My Cafe', latitude: leipzig_lat(0), longitude: leipzig_lon(0),
                           source: :manual, name_locked_at: Time.current)
    stub_at(selfhosted_url, leipzig_lat(0), json_response(photon_body(leipzig_lat(0), leipzig_lon(0),
                                                                      name: 'Provider Name')))
    place_fixture('place_name_locked', user, place)
  end

  it 'keeps the identity keys and, with the stored store_geodata false, only the indexed properties',
     fixture: :place_privacy_mode do
    user = create(:user, email: 'w5b-place-privacy-mode@example.test')
    selfhosted_photon(store_geodata: false)
    place = create(:place, user:, name: 'Waypoint', latitude: leipzig_lat(0), longitude: leipzig_lon(0),
                           source: :gpx_waypoint,
                           geodata: { 'external_place_id' => 'gpx:fixture', 'semantic_type' => 'poi' })
    stub_at(selfhosted_url, leipzig_lat(0), json_response(photon_body(leipzig_lat(0), leipzig_lon(0))))
    place_fixture('place_privacy_mode', user, place)
  end

  it 'raises when a provider name would exceed the 255-character column limit', fixture: :place_name_too_long do
    user = create(:user, email: 'w5b-place-name-too-long@example.test')
    selfhosted_photon
    place = create(:place, user:, name: 'Suggested place', latitude: leipzig_lat(0), longitude: leipzig_lon(0),
                           source: :manual)
    stub_at(selfhosted_url, leipzig_lat(0), json_response(photon_body(leipzig_lat(0), leipzig_lon(0), name: 'A' * 300)))
    place_fixture('place_name_too_long', user, place)
  end

  it 'raises when a provider result carries no coordinates', fixture: :place_without_coordinates do
    user = create(:user, email: 'w5b-place-without-coordinates@example.test')
    selfhosted_photon
    place = create(:place, user:, name: 'Suggested place', latitude: leipzig_lat(0), longitude: leipzig_lon(0),
                           source: :manual)
    body = { type: 'FeatureCollection',
             features: [{ type: 'Feature', properties: { name: 'No Coords', country: 'Germany' },
                          geometry: { type: 'Point', coordinates: nil } }] }
    stub_at(selfhosted_url, leipzig_lat(0), json_response(body))
    place_fixture('place_without_coordinates', user, place)
  end

  it "queries the place's lonlat but rebuilds lonlat from its decimals", fixture: :place_lonlat_from_decimals do
    user = create(:user, email: 'w5b-place-lonlat-decimals@example.test')
    selfhosted_photon
    place = create(:place, user:, name: 'Suggested place', latitude: leipzig_lat(0), longitude: leipzig_lon(0),
                           source: :manual)
    place.update_columns(lonlat: leipzig(0.0003, 0.0009))
    stub_at(selfhosted_url, leipzig_lat(0.0003),
            json_response(photon_body(leipzig_lat(0.0003), leipzig_lon(0.0009), name: 'Decimal Place')))
    place_fixture('place_lonlat_from_decimals', user, place)
  end

  def with_env(env)
    env.each { |name, value| ENV[name] = value }
    InstanceSettings::Resolver.reset!
    yield
  ensure
    env.each_key { |name| ENV.delete(name) }
    InstanceSettings::Resolver.reset!
  end

  def store_undecryptable(key, clear_text)
    ciphertext = ActiveRecord::Encryption::Encryptor.new.encrypt(
      clear_text, key_provider: ActiveRecord::Encryption::DerivedSecretKeyProvider.new('w5b-rotated-away')
    )
    InstanceSetting.connection.exec_update(
      InstanceSetting.sanitize_sql_array(['UPDATE instance_settings SET encrypted_value = ? WHERE key = ?',
                                          ciphertext, key])
    )
  end

  def config_case(name, settings, env: {}, after_create: nil)
    InstanceSetting.delete_all
    settings.each { |key, value| InstanceSetting.create!(key: key.to_s, value: value) }
    after_create&.call
    with_env(env) do
      { 'name' => name, 'input' => { 'instance_settings' => instance_setting_rows }, 'env' => env,
        'expected' => config_dump }
    end
  end

  it 'resolves the provider chain, pins, stored secrets, stored false values and rate clamps',
     fixture: :config_resolution do
    selfhosted = { photon_api_host: 'photon.selfhosted.example.test' }
    cases = [
      config_case('env_pin_beats_stored', selfhosted, env: { 'NOMINATIM_API_HOST' => 'nominatim.pinned.example.test' }),
      config_case('stored_encrypted_key_decrypts', selfhosted.merge(photon_api_key: 'w5b-k-01')),
      config_case('undecryptable_secret_absent', selfhosted.merge(photon_api_key: 'w5b-k-05'),
                  after_create: -> { store_undecryptable('photon_api_key', 'w5b-k-05') }),
      config_case('no_candidate', {}),
      config_case('no_candidate_store_geodata_false', { store_geodata: false }),
      config_case('stored_store_geodata_false', selfhosted.merge(store_geodata: false)),
      config_case('nominatim_stored_http', { nominatim_api_host: 'nominatim.selfhosted.example.test',
                                             nominatim_api_use_https: false }),
      config_case('photon_https_forced_komoot', { photon_api_host: 'photon.komoot.io', photon_api_use_https: false }),
      config_case('photon_https_forced_chibigeo', { photon_api_host: 'app.chibigeo.com/v1/photon',
                                                    photon_api_key: 'w5b-k-02', photon_api_use_https: false }),
      config_case('rps_komoot_locked', { photon_api_host: 'photon.komoot.io', reverse_geocoding_rps: '40' }),
      config_case('rps_chibigeo_clamped', { photon_api_host: 'app.chibigeo.com/v1/photon',
                                            photon_api_key: 'w5b-k-02', reverse_geocoding_rps: '40' }),
      config_case('rps_blank', selfhosted.merge(reverse_geocoding_rps: '')),
      config_case('rps_zero', selfhosted.merge(reverse_geocoding_rps: '0')),
      config_case('rps_custom', selfhosted.merge(reverse_geocoding_rps: '5'))
    ]
    write_fixture('geocoding', 'config_resolution', { 'cases' => cases })
  end

  def search_case(name, settings: nil, config: nil, responses: [], calls: 1)
    Rails.cache.clear
    InstanceSetting.delete_all
    settings&.each { |key, value| InstanceSetting.create!(key: key.to_s, value: value) }
    InstanceSettings::Resolver.reset!
    resolved = config || Geocoding::Config.resolved_config
    @search_index = (@search_index || 0) + 1
    lat = leipzig_lat(0.001 * @search_index)
    responses.each { |pattern, response| stub_at(pattern, lat, response) }
    throttles = 0
    allow(Geocoding::RateLimiter).to receive(:throttle).and_wrap_original do |original, *args, **kwargs, &block|
      throttles += 1
      original.call(*args, **kwargs, &block)
    end
    first_request = http.size
    outcomes = Array.new(calls) { search_outcome(resolved, config.nil?, lat) }
    { 'name' => name, 'input' => { 'instance_settings' => instance_setting_rows }, 'config' => config_dump(resolved),
      'query' => [lat, leipzig_lon], 'outcomes' => outcomes, 'throttle_calls' => throttles,
      'requests' => http[first_request..], 'cache' => geocoder_cache }
  end

  def search_outcome(config, resolved, lat)
    before = http.size
    found = if resolved
              Geocoding::Search.call(user: nil, query: [lat, leipzig_lon])
            else
              Geocoding::Search.with_config(config:, query: [lat, leipzig_lon])
            end
    { 'results' => found.size, 'data' => found.map(&:data), 'requests' => http.size - before }
  rescue StandardError => e
    { 'raised' => e.class.name, 'message' => e.message, 'requests' => http.size - before }
  end

  it 'Rails repeats an HTTP 200 empty binary lookup', fixture: :search_outcomes do
    c = search_case('empty_binary',
                    settings: { photon_api_host: 'photon.selfhosted.example.test', photon_api_use_https: true },
                    responses: [[selfhosted_url, json_response('')]], calls: 2)
    expect(c['outcomes']).to eq(Array.new(2) do
      { 'raised' => 'Geocoder::ResponseParseError', 'message' => 'Geocoder::ResponseParseError', 'requests' => 1 }
    end)
    expect(c['requests'].size).to eq(2)
    expect(c['cache']).to eq([{ 'key' => 'https://photon.selfhosted.example.test/reverse?lang=en&lat=51.3407&lon=12.3731',
                               'value' => '' }])
  end

  it 'Rails caches an HTTP 200 empty FeatureCollection', fixture: :search_outcomes do
    body = { type: 'FeatureCollection', features: [] }.to_json
    c = search_case('empty_features',
                    settings: { photon_api_host: 'photon.selfhosted.example.test', photon_api_use_https: true },
                    responses: [[selfhosted_url, json_response(body)]], calls: 2)
    expect(c['outcomes']).to eq([{ 'results' => 0, 'data' => [], 'requests' => 1 },
                                 { 'results' => 0, 'data' => [], 'requests' => 0 }])
    expect(c['requests'].size).to eq(1)
    expect(c['cache']).to eq([{ 'key' => 'https://photon.selfhosted.example.test/reverse?lang=en&lat=51.3407&lon=12.3731',
                               'value' => body }])
  end

  { 400 => 'Geocoder::InvalidRequest', 401 => 'Geocoder::RequestDenied',
    402 => 'Geocoder::OverQueryLimitError', 404 => nil, 429 => 'Geocoder::OverQueryLimitError',
    503 => 'Geocoder::ServiceUnavailable' }.each do |status, error|
    it "Rails repeats HTTP #{status} without caching", fixture: :search_outcomes do
      c = search_case("status_#{status}",
                      settings: { photon_api_host: 'photon.selfhosted.example.test', photon_api_use_https: true },
                      responses: [[selfhosted_url, json_response(photon_body(leipzig_lat, leipzig_lon), status:)]],
                      calls: 2)
      outcome = if error
                  { 'raised' => error, 'message' => error, 'requests' => 1 }
                else
                  { 'results' => 1, 'data' => [photon_feature(leipzig_lat, leipzig_lon).deep_stringify_keys],
                    'requests' => 1 }
                end
      expect(c['outcomes']).to eq([outcome, outcome])
      expect(c['requests'].size).to eq(2)
      expect(c['cache']).to eq([])
    end
  end

  it 'Rails repeats a timed-out lookup without caching', fixture: :search_outcomes do
    c = search_case('timeout_boundary',
                    settings: { photon_api_host: 'photon.selfhosted.example.test', photon_api_use_https: true },
                    responses: [[selfhosted_url, :timeout]], calls: 2)
    expect(c['outcomes']).to eq(Array.new(2) do
      { 'raised' => 'Geocoder::LookupTimeout', 'message' => 'Geocoder::LookupTimeout', 'requests' => 1 }
    end)
    expect(c['requests'].size).to eq(2)
    expect(c['cache']).to eq([])
  end

  it 'records what the search raises or returns for each provider body and status', fixture: :search_outcomes do
    photon = { photon_api_host: 'photon.selfhosted.example.test', photon_api_use_https: true }
    nominatim = { nominatim_api_host: 'nominatim.selfhosted.example.test', nominatim_api_use_https: false }
    locationiq = { locationiq_api_key: 'w5b-k-04' }
    nominatim_url = %r{http://nominatim\.selfhosted\.example\.test/reverse}
    locationiq_url = %r{https://us1\.locationiq\.com/v1/reverse}
    geoapify_url = %r{https://api\.geoapify\.com/v1/geocode/reverse}
    locationiq_errors = ['Invalid key', 'Key not active - Please write to contact@unwiredlabs.com', 'Rate Limited',
                         'Unknown error - Please try again after some time']
    specs = [
      ['photon_429', photon, selfhosted_url, { status: 429, body: 'slow down' }],
      ['photon_503', photon, selfhosted_url, { status: 503, body: 'unavailable' }],
      ['photon_invalid_json_200', photon, selfhosted_url, { status: 200, body: 'not json' }, 2],
      ['photon_cache_hit', photon, selfhosted_url, json_response(photon_body(leipzig_lat, leipzig_lon)), 2],
      ['photon_empty_features', photon, selfhosted_url, json_response({ type: 'FeatureCollection', features: [] })],
      ['photon_features_null', photon, selfhosted_url, json_response({ type: 'FeatureCollection', features: nil })],
      ['photon_not_feature_collection', photon, selfhosted_url, json_response({ type: 'Feature' })],
      ['photon_json_array', photon, selfhosted_url, json_response([])],
      ['photon_timeout', photon, selfhosted_url, :timeout],
      ['nominatim_bandwidth_text', nominatim, nominatim_url, { status: 200, body: 'Bandwidth limit exceeded' }],
      ['nominatim_error_object', nominatim, nominatim_url, json_response({ error: 'Unable to geocode' })],
      *locationiq_errors.each_with_index.map do |error, i|
        ["locationiq_error_#{i + 1}", locationiq, locationiq_url, json_response({ error: })]
      end,
      ['locationiq_empty_array', locationiq, locationiq_url, json_response([])],
      ['geoapify_status_code_500', { geoapify_api_key: 'w5b-k-03' }, geoapify_url,
       json_response({ statusCode: 500, message: 'Internal' })]
    ]
    cases = specs.map do |name, settings, url, response, calls|
      search_case(name, settings:, responses: [[url, response]], calls: calls || 1)
    end
    cases << search_case('photon_missing_host',
                         config: Geocoding::Config.new(source: :stored, provider: :photon, host: nil))
    cases << search_case('geoapify_missing_key',
                         config: Geocoding::Config.new(source: :stored, provider: :geoapify, api_key: ''))
    write_fixture('geocoding', 'search_outcomes', { 'cases' => cases })
  end
end
