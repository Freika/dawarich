# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Phoenix fixture: Rails reverse geocoding' do
  before do
    use_real_geocoding_lookups
    allow(Geocoding::RateLimiter).to receive(:sleep)
  end

  def postgis_build
    full = ActiveRecord::Base.connection.select_value('SELECT postgis_full_version()')
    postgis = full[/POSTGIS="([^"\s]+)/, 1]
    proj = full[/PROJ="([^"\s]+)/, 1]
    "POSTGIS=#{postgis} PROJ=#{proj}"
  end

  def rows(sql, *binds)
    ActiveRecord::Base.connection.select_values(ActiveRecord::Base.sanitize_sql_array([sql, *binds])).map do |json|
      JSON.parse(json)
    end
  end

  def user_row(user)
    rows('SELECT row_to_json(x)::text FROM (SELECT id, email, settings FROM users WHERE id = ?) x', user.id).first
  end

  def instance_setting_rows
    rows(<<~SQL.squish)
      SELECT row_to_json(x)::text FROM (
        SELECT id, key, value::text AS value, encrypted_value FROM instance_settings ORDER BY id
      ) x
    SQL
  end

  # Rails sets reverse_geocoded_at / name_locked_at from the wall clock; only
  # whether the call touched it is deterministic, never the value itself.
  def clock_state(value)
    value.present? ? 'set' : nil
  end

  def point_row(point)
    row = rows(<<~SQL.squish, point.id).first
      SELECT row_to_json(x)::text FROM (
        SELECT id, user_id, ST_AsText(lonlat) AS lonlat_wkt, "timestamp", city, country_name, country_id,
               geodata::text AS geodata, reverse_geocoded_at::text AS reverse_geocoded_at
        FROM points WHERE id = ?
      ) x
    SQL
    row.merge('reverse_geocoded_at' => clock_state(row['reverse_geocoded_at']))
  end

  def place_row(place)
    row = rows(<<~SQL.squish, place.id).first
      SELECT row_to_json(x)::text FROM (
        SELECT id, user_id, name, ST_AsText(lonlat) AS lonlat_wkt, source, import_id,
               name_locked_at::text AS name_locked_at, geodata::text AS geodata
        FROM places WHERE id = ?
      ) x
    SQL
    row.merge('name_locked_at' => clock_state(row['name_locked_at']))
  end

  def all_places_for(user)
    rows('SELECT row_to_json(x)::text FROM (SELECT id, name, ST_AsText(lonlat) AS lonlat_wkt, source, ' \
         'geodata::text AS geodata FROM places WHERE user_id = ? ORDER BY id) x', user.id)
  end

  def country_row(country)
    rows(<<~SQL.squish, country.id).first
      SELECT row_to_json(x)::text FROM (
        SELECT id, name, iso_a2, iso_a3, ST_AsText(geom) AS geom_wkt FROM countries WHERE id = ?
      ) x
    SQL
  end

  # The gem stamps every request with a User-Agent naming the real production
  # host; that identity string is irrelevant to what these fixtures assert
  # and must never appear in a golden fixture (synthetic-hosts-only rule).
  def webmock_requests(pattern)
    WebMock::RequestRegistry.instance.requested_signatures.hash.keys
                            .select { |sig| sig.uri.to_s.match?(pattern) }
                            .map do |sig|
      { 'method' => sig.method.to_s, 'url' => sig.uri.to_s, 'headers' => sig.headers.except('User-Agent') }
    end
  end

  def cache_entry(config, coordinates)
    lookup = Geocoding::UserLookup.build(config)
    query = Geocoder::Query.new(coordinates, lookup: Geocoding::Providers.gem_handle(config.provider))
    key = lookup.send(:cache_key, query)
    { 'key' => key, 'value' => lookup.send(:cache)[key] }
  end

  def normalized_dump(body)
    data = JSON.parse(body)
    data = data['features'].first if data.is_a?(Hash) && data['features'].is_a?(Array)
    data = data.first if data.is_a?(Array)
    Geocoding::ResultNormalizer.from_data(data || {}).deep_stringify_keys
  rescue JSON::ParserError, TypeError
    { 'error' => 'unparseable' }
  end

  def write_fixture(name, data)
    path = Rails.root.join("app-phoenix/test/fixtures/geocoding/#{name}.json")
    FileUtils.mkdir_p(path.dirname)
    File.write(path, "#{JSON.pretty_generate(data.merge('postgis_build' => postgis_build))}\n")
  end

  def photon_body(city: 'Leipzig', country: 'Germany', code: 'DE', name: 'Testplatz', lon: 12.3731, lat: 51.3397)
    {
      type: 'FeatureCollection',
      features: [
        { type: 'Feature',
          properties: { city: city, country: country, countrycode: code, name: name, osm_id: 42,
                        osm_type: 'N', osm_key: 'amenity', osm_value: 'cafe' },
          geometry: { type: 'Point', coordinates: [lon, lat] } }
      ]
    }.to_json
  end

  it 'reverse-geocodes a point through Photon (Komoot) over forced HTTPS at the locked 1 rps' do
    user = create(:user, email: 'w5b-photon-komoot@example.test')
    configure_instance_geocoding(photon_api_host: 'photon.komoot.io')
    point = create(:point, user: user, lonlat: 'POINT(12.3731 51.3397)', reverse_geocoded_at: nil)
    point_before = point_row(point)
    stub_request(:get, %r{https://photon\.komoot\.io/reverse}).to_return(
      status: 200, body: photon_body, headers: { 'Content-Type' => 'application/json' }
    )

    ReverseGeocoding::Points::FetchData.new(point.id).call

    config = Geocoding::Config.resolved_config
    fixture = {
      'input' => { 'users' => [user_row(user)], 'points' => [point_before],
                   'instance_settings' => instance_setting_rows },
      'config' => { 'source' => config.source.to_s, 'provider' => config.provider.to_s, 'host' => config.host,
                     'use_https' => config.use_https, 'rps' => config.rps },
      'requests' => webmock_requests(/photon\.komoot\.io/),
      'normalized' => normalized_dump(photon_body),
      'expected' => { 'point' => point_row(point) }
    }
    write_fixture('photon_komoot', fixture)
  end

  it "sends the self-hosted Photon's X-Api-Key header over HTTP" do
    user = create(:user, email: 'w5b-photon-selfhosted-key@example.test')
    configure_instance_geocoding(photon_api_host: 'photon.selfhosted.example.test', photon_api_use_https: false,
                                 photon_api_key: 'w5b-k-01')
    point = create(:point, user: user, lonlat: 'POINT(12.3731 51.3397)', reverse_geocoded_at: nil)
    point_before = point_row(point)
    stub_request(:get, %r{http://photon\.selfhosted\.example\.test/reverse}).to_return(
      status: 200, body: photon_body, headers: { 'Content-Type' => 'application/json' }
    )

    ReverseGeocoding::Points::FetchData.new(point.id).call

    config = Geocoding::Config.resolved_config
    fixture = {
      'input' => { 'users' => [user_row(user)], 'points' => [point_before],
                   'instance_settings' => instance_setting_rows },
      'config' => { 'source' => config.source.to_s, 'provider' => config.provider.to_s, 'host' => config.host,
                     'use_https' => config.use_https, 'api_key' => config.api_key },
      'requests' => webmock_requests(/photon\.selfhosted\.example\.test/),
      'cache' => cache_entry(config, [51.3397, 12.3731]),
      'normalized' => normalized_dump(photon_body),
      'expected' => { 'point' => point_row(point) }
    }
    write_fixture('photon_selfhosted_key', fixture)
  end

  it "resolves ChibiGeo's proxy path host and digests its rate-limit bucket per key" do
    user = create(:user, email: 'w5b-photon-chibigeo@example.test')
    configure_instance_geocoding(photon_api_host: 'app.chibigeo.com/v1/photon', photon_api_key: 'w5b-k-02')
    point = create(:point, user: user, lonlat: 'POINT(12.3731 51.3397)', reverse_geocoded_at: nil)
    point_before = point_row(point)
    stub_request(:get, %r{https://app\.chibigeo\.com/v1/photon/reverse}).to_return(
      status: 200, body: photon_body, headers: { 'Content-Type' => 'application/json' }
    )

    ReverseGeocoding::Points::FetchData.new(point.id).call

    config = Geocoding::Config.resolved_config
    fixture = {
      'input' => { 'users' => [user_row(user)], 'points' => [point_before],
                   'instance_settings' => instance_setting_rows },
      'config' => { 'source' => config.source.to_s, 'provider' => config.provider.to_s, 'host' => config.host,
                     'rps' => config.rps, 'chibigeo' => Geocoding::Providers.chibigeo?(config.provider, config.host),
                     'rate_limit_key' => Geocoding::RateLimiter.key_for(config) },
      'requests' => webmock_requests(/chibigeo/),
      'normalized' => normalized_dump(photon_body),
      'expected' => { 'point' => point_row(point) }
    }
    write_fixture('photon_chibigeo', fixture)
  end

  it 'includes apiKey in the geoapify cache key, upcases the country code, and records a 500' do
    user = create(:user, email: 'w5b-geoapify@example.test')
    configure_instance_geocoding(geoapify_api_key: 'w5b-k-03')
    ok_point = create(:point, user: user, lonlat: 'POINT(12.3731 51.3397)', reverse_geocoded_at: nil)
    error_point = create(:point, user: user, lonlat: 'POINT(12.38 51.34)', reverse_geocoded_at: nil)
    points_before = [ok_point, error_point].map { |p| point_row(p) }
    geoapify_body = { type: 'FeatureCollection',
                      features: [{ type: 'Feature',
                                   properties: { city: 'Leipzig', country: 'Germany', country_code: 'de',
                                                 name: 'Testplatz', lon: 12.3731, lat: 51.3397 },
                                   geometry: { type: 'Point', coordinates: [12.3731, 51.3397] } }] }.to_json
    stub_request(:get, %r{https://api\.geoapify\.com/v1/geocode/reverse})
      .with(query: hash_including('lat' => '51.3397'))
      .to_return(status: 200, body: geoapify_body, headers: { 'Content-Type' => 'application/json' })
    stub_request(:get, %r{https://api\.geoapify\.com/v1/geocode/reverse})
      .with(query: hash_including('lat' => '51.34'))
      .to_return(status: 500, body: '', headers: {})

    ReverseGeocoding::Points::FetchData.new(ok_point.id).call
    ReverseGeocoding::Points::FetchData.new(error_point.id).call

    config = Geocoding::Config.resolved_config
    fixture = {
      'input' => { 'users' => [user_row(user)], 'points' => points_before,
                   'instance_settings' => instance_setting_rows },
      'config' => { 'source' => config.source.to_s, 'provider' => config.provider.to_s, 'api_key' => config.api_key },
      'cache' => cache_entry(config, [51.3397, 12.3731]),
      'requests' => webmock_requests(/api\.geoapify\.com/),
      'normalized' => normalized_dump(geoapify_body),
      'expected' => { 'ok_point' => point_row(ok_point), 'error_point' => point_row(error_point) }
    }
    write_fixture('geoapify', fixture)
  end

  it 'maps a flat Nominatim town onto city, lowercases the code, and records a bandwidth-limit error' do
    user = create(:user, email: 'w5b-nominatim@example.test')
    configure_instance_geocoding(nominatim_api_host: 'nominatim.selfhosted.example.test',
                                 nominatim_api_use_https: false)
    ok_point = create(:point, user: user, lonlat: 'POINT(12.3731 51.3397)', reverse_geocoded_at: nil)
    error_point = create(:point, user: user, lonlat: 'POINT(12.38 51.34)', reverse_geocoded_at: nil)
    points_before = [ok_point, error_point].map { |p| point_row(p) }
    nominatim_body = { display_name: 'Testplatz, Leipzig, Germany', lat: '51.3397', lon: '12.3731',
                       address: { town: 'Leipzig', country: 'Germany', country_code: 'de' } }.to_json
    stub_request(:get, %r{http://nominatim\.selfhosted\.example\.test/reverse})
      .with(query: hash_including('lat' => '51.3397'))
      .to_return(status: 200, body: nominatim_body, headers: { 'Content-Type' => 'application/json' })
    stub_request(:get, %r{http://nominatim\.selfhosted\.example\.test/reverse})
      .with(query: hash_including('lat' => '51.34'))
      .to_return(status: 200, body: { error: 'Bandwidth limit exceeded' }.to_json,
                 headers: { 'Content-Type' => 'application/json' })

    ReverseGeocoding::Points::FetchData.new(ok_point.id).call
    ReverseGeocoding::Points::FetchData.new(error_point.id).call

    config = Geocoding::Config.resolved_config
    fixture = {
      'input' => { 'users' => [user_row(user)], 'points' => points_before,
                   'instance_settings' => instance_setting_rows },
      'config' => { 'source' => config.source.to_s, 'provider' => config.provider.to_s, 'host' => config.host,
                     'use_https' => config.use_https },
      'requests' => webmock_requests(/nominatim\.selfhosted\.example\.test/),
      'normalized' => normalized_dump(nominatim_body),
      'expected' => { 'ok_point' => point_row(ok_point), 'error_point' => point_row(error_point) }
    }
    write_fixture('nominatim', fixture)
  end

  it 'returns a LocationIQ array result and records an invalid-key error' do
    user = create(:user, email: 'w5b-locationiq@example.test')
    configure_instance_geocoding(locationiq_api_key: 'w5b-k-04')
    ok_point = create(:point, user: user, lonlat: 'POINT(12.3731 51.3397)', reverse_geocoded_at: nil)
    error_point = create(:point, user: user, lonlat: 'POINT(12.38 51.34)', reverse_geocoded_at: nil)
    points_before = [ok_point, error_point].map { |p| point_row(p) }
    locationiq_body = [{ display_name: 'Testplatz, Leipzig, Germany', lat: '51.3397', lon: '12.3731',
                          address: { city: 'Leipzig', country: 'Germany', country_code: 'de' } }].to_json
    stub_request(:get, %r{https://us1\.locationiq\.com/v1/reverse})
      .with(query: hash_including('lat' => '51.3397'))
      .to_return(status: 200, body: locationiq_body, headers: { 'Content-Type' => 'application/json' })
    stub_request(:get, %r{https://us1\.locationiq\.com/v1/reverse})
      .with(query: hash_including('lat' => '51.34'))
      .to_return(status: 200, body: { error: 'Invalid key' }.to_json,
                 headers: { 'Content-Type' => 'application/json' })

    ReverseGeocoding::Points::FetchData.new(ok_point.id).call
    ReverseGeocoding::Points::FetchData.new(error_point.id).call

    config = Geocoding::Config.resolved_config
    fixture = {
      'input' => { 'users' => [user_row(user)], 'points' => points_before,
                   'instance_settings' => instance_setting_rows },
      'config' => { 'source' => config.source.to_s, 'provider' => config.provider.to_s, 'api_key' => config.api_key },
      'requests' => webmock_requests(/us1\.locationiq\.com/),
      'normalized' => normalized_dump(locationiq_body),
      'expected' => { 'ok_point' => point_row(ok_point), 'error_point' => point_row(error_point) }
    }
    write_fixture('locationiq', fixture)
  end

  it 'drops the raw provider payload but keeps identity fields when store_geodata is false' do
    user = create(:user, email: 'w5b-store-geodata-false@example.test')
    configure_instance_geocoding(photon_api_host: 'photon.selfhosted.example.test', photon_api_use_https: true)
    allow(DawarichSettings).to receive(:store_geodata?).and_return(false)
    point = create(:point, user: user, lonlat: 'POINT(12.3731 51.3397)', reverse_geocoded_at: nil)
    point_before = point_row(point)
    stub_request(:get, %r{https://photon\.selfhosted\.example\.test/reverse}).to_return(
      status: 200, body: photon_body, headers: { 'Content-Type' => 'application/json' }
    )

    ReverseGeocoding::Points::FetchData.new(point.id).call

    fixture = {
      'input' => { 'users' => [user_row(user)], 'points' => [point_before],
                   'instance_settings' => instance_setting_rows },
      'store_geodata' => false,
      'requests' => webmock_requests(/photon\.selfhosted\.example\.test/),
      'expected' => { 'point' => point_row(point) }
    }
    write_fixture('store_geodata_false', fixture)
  end

  it 'resolves a country name alias and rejects a mismatched country code' do
    user = create(:user, email: 'w5b-country-alias@example.test')
    configure_instance_geocoding(photon_api_host: 'photon.selfhosted.example.test', photon_api_use_https: true)
    country = create(:country, name: 'United States of America', iso_a2: 'US', iso_a3: 'USA',
                                geom: 'MULTIPOLYGON (((-100 30, -100 31, -99 31, -99 30, -100 30)))')
    alias_point = create(:point, user: user, lonlat: 'POINT(-99.5 30.5)', reverse_geocoded_at: nil)
    mismatch_point = create(:point, user: user, lonlat: 'POINT(-99.5 30.6)', reverse_geocoded_at: nil)
    points_before = [alias_point, mismatch_point].map { |p| point_row(p) }
    alias_body = photon_body(city: 'Fixture City', country: 'United States', code: 'US', lon: -99.5, lat: 30.5)
    mismatch_body = photon_body(city: 'Fixture City', country: 'United States of America', code: 'ZZ', lon: -99.5,
                                lat: 30.6)
    stub_request(:get, %r{https://photon\.selfhosted\.example\.test/reverse})
      .with(query: hash_including('lat' => '30.5'))
      .to_return(status: 200, body: alias_body, headers: { 'Content-Type' => 'application/json' })
    stub_request(:get, %r{https://photon\.selfhosted\.example\.test/reverse})
      .with(query: hash_including('lat' => '30.6'))
      .to_return(status: 200, body: mismatch_body, headers: { 'Content-Type' => 'application/json' })

    ReverseGeocoding::Points::FetchData.new(alias_point.id).call
    ReverseGeocoding::Points::FetchData.new(mismatch_point.id).call

    fixture = {
      'input' => { 'users' => [user_row(user)], 'countries' => [country_row(country)], 'points' => points_before,
                   'instance_settings' => instance_setting_rows },
      'requests' => webmock_requests(/photon\.selfhosted\.example\.test/),
      'expected' => { 'alias_point' => point_row(alias_point), 'mismatch_point' => point_row(mismatch_point) }
    }
    write_fixture('country_alias_and_mismatch', fixture)
  end

  it 'folds an existing, a repeated and a new osm_id sibling into places' do
    user = create(:user, email: 'w5b-place-siblings@example.test')
    configure_instance_geocoding(photon_api_host: 'photon.selfhosted.example.test', photon_api_use_https: true)
    existing = create(:place, user: user, name: 'Old Name', latitude: 51.3397, longitude: 12.3731, source: :photon,
                               geodata: { 'properties' => { 'osm_id' => 100 } })
    place = create(:place, user: user, name: 'Suggested place', latitude: 51.3397, longitude: 12.3731,
                            source: :manual)
    places_before = [place_row(existing), place_row(place)]
    body = {
      type: 'FeatureCollection',
      features: [
        { type: 'Feature', properties: { name: 'Self Update', country: 'Germany', osm_id: 999, osm_type: 'N',
                                          osm_key: 'amenity', osm_value: 'cafe' },
          geometry: { type: 'Point', coordinates: [12.3731, 51.3397] } },
        { type: 'Feature', properties: { name: 'Existing Sibling', country: 'Germany', osm_id: 100, osm_type: 'N',
                                          osm_key: 'amenity', osm_value: 'bakery' },
          geometry: { type: 'Point', coordinates: [12.37305, 51.33975] } },
        { type: 'Feature', properties: { name: 'Duplicate', country: 'Germany', osm_id: 200, osm_type: 'N',
                                          osm_key: 'amenity', osm_value: 'bar' },
          geometry: { type: 'Point', coordinates: [12.3732, 51.3398] } },
        { type: 'Feature', properties: { name: 'Duplicate', country: 'Germany', osm_id: 200, osm_type: 'N',
                                          osm_key: 'amenity', osm_value: 'bar' },
          geometry: { type: 'Point', coordinates: [12.3732, 51.3398] } },
        { type: 'Feature', properties: { name: 'Brand New', country: 'Germany', osm_id: 300, osm_type: 'N',
                                          osm_key: 'amenity', osm_value: 'shop' },
          geometry: { type: 'Point', coordinates: [12.3733, 51.3399] } }
      ]
    }.to_json
    stub_request(:get, %r{https://photon\.selfhosted\.example\.test/reverse}).to_return(
      status: 200, body: body, headers: { 'Content-Type' => 'application/json' }
    )

    ReverseGeocoding::Places::FetchData.new(place.id).call

    fixture = {
      'input' => { 'users' => [user_row(user)], 'places' => places_before,
                   'instance_settings' => instance_setting_rows },
      'requests' => webmock_requests(/photon\.selfhosted\.example\.test/),
      'expected' => { 'places' => all_places_for(user) }
    }
    write_fixture('place_siblings', fixture)
  end

  it "keeps a name-locked place's name and source through reverse geocoding" do
    user = create(:user, email: 'w5b-place-name-locked@example.test')
    configure_instance_geocoding(photon_api_host: 'photon.selfhosted.example.test', photon_api_use_https: true)
    place = create(:place, user: user, name: 'My Cafe', latitude: 51.3397, longitude: 12.3731, source: :manual,
                            name_locked_at: Time.current)
    place_before = place_row(place)
    stub_request(:get, %r{https://photon\.selfhosted\.example\.test/reverse}).to_return(
      status: 200, body: photon_body(name: 'Provider Name'), headers: { 'Content-Type' => 'application/json' }
    )

    ReverseGeocoding::Places::FetchData.new(place.id).call

    fixture = {
      'input' => { 'users' => [user_row(user)], 'places' => [place_before],
                   'instance_settings' => instance_setting_rows },
      'requests' => webmock_requests(/photon\.selfhosted\.example\.test/),
      'expected' => { 'place' => place_row(place) }
    }
    write_fixture('place_name_locked', fixture)
  end

  it 'keeps identity keys and, under privacy mode, only the indexed properties' do
    user = create(:user, email: 'w5b-place-privacy-mode@example.test')
    configure_instance_geocoding(photon_api_host: 'photon.selfhosted.example.test', photon_api_use_https: true)
    allow(DawarichSettings).to receive(:store_geodata?).and_return(false)
    place = create(:place, user: user, name: 'Waypoint', latitude: 51.3397, longitude: 12.3731,
                            source: :gpx_waypoint,
                            geodata: { 'external_place_id' => 'gpx:fixture', 'semantic_type' => 'poi' })
    place_before = place_row(place)
    stub_request(:get, %r{https://photon\.selfhosted\.example\.test/reverse}).to_return(
      status: 200, body: photon_body, headers: { 'Content-Type' => 'application/json' }
    )

    ReverseGeocoding::Places::FetchData.new(place.id).call

    fixture = {
      'input' => { 'users' => [user_row(user)], 'places' => [place_before],
                   'instance_settings' => instance_setting_rows },
      'store_geodata' => false,
      'requests' => webmock_requests(/photon\.selfhosted\.example\.test/),
      'expected' => { 'place' => place_row(place) }
    }
    write_fixture('place_privacy_mode', fixture)
  end

  it 'raises when a provider name would exceed the 255-character column limit' do
    user = create(:user, email: 'w5b-place-name-too-long@example.test')
    configure_instance_geocoding(photon_api_host: 'photon.selfhosted.example.test', photon_api_use_https: true)
    place = create(:place, user: user, name: 'Suggested place', latitude: 51.3397, longitude: 12.3731,
                            source: :manual)
    place_before = place_row(place)
    long_name = 'A' * 300
    body = { type: 'FeatureCollection',
             features: [{ type: 'Feature', properties: { name: long_name, country: 'Germany' },
                           geometry: { type: 'Point', coordinates: [12.3731, 51.3397] } }] }.to_json
    stub_request(:get, %r{https://photon\.selfhosted\.example\.test/reverse}).to_return(
      status: 200, body: body, headers: { 'Content-Type' => 'application/json' }
    )

    error = nil
    begin
      ReverseGeocoding::Places::FetchData.new(place.id).call
    rescue StandardError => e
      error = e
    end

    fixture = {
      'input' => { 'users' => [user_row(user)], 'places' => [place_before],
                   'instance_settings' => instance_setting_rows },
      'requests' => webmock_requests(/photon\.selfhosted\.example\.test/),
      'expected' => { 'raised' => error&.class&.name, 'place_unchanged' => place_row(place) }
    }
    write_fixture('place_name_too_long', fixture)
  end

  it 'raises when a provider result carries no coordinates' do
    user = create(:user, email: 'w5b-place-without-coordinates@example.test')
    configure_instance_geocoding(photon_api_host: 'photon.selfhosted.example.test', photon_api_use_https: true)
    place = create(:place, user: user, name: 'Suggested place', latitude: 51.3397, longitude: 12.3731,
                            source: :manual)
    place_before = place_row(place)
    body = { type: 'FeatureCollection',
             features: [{ type: 'Feature', properties: { name: 'No Coords', country: 'Germany' },
                           geometry: { type: 'Point', coordinates: nil } }] }.to_json
    stub_request(:get, %r{https://photon\.selfhosted\.example\.test/reverse}).to_return(
      status: 200, body: body, headers: { 'Content-Type' => 'application/json' }
    )

    error = nil
    begin
      ReverseGeocoding::Places::FetchData.new(place.id).call
    rescue StandardError => e
      error = e
    end

    fixture = {
      'input' => { 'users' => [user_row(user)], 'places' => [place_before],
                   'instance_settings' => instance_setting_rows },
      'requests' => webmock_requests(/photon\.selfhosted\.example\.test/),
      'expected' => { 'raised' => error&.class&.name, 'place_unchanged' => place_row(place) }
    }
    write_fixture('place_without_coordinates', fixture)
  end
end
