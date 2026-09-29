# frozen_string_literal: true

require 'rails_helper'

module IngestUnitsOracle
  FEATURE = lambda do |coordinates, properties|
    {
      'type' => 'Feature', 'geometry' => { 'type' => 'Point', 'coordinates' => coordinates },
      'properties' => properties
    }
  end

  ISO = '2024-01-01T12:00:00Z'

  STRINGS = [
    '0', '12', ' 12', "\t9", '9 ', '12abc', '-7', '+7', '1_000', '1__0', '_1', '12.9', '-12.9',
    'abc', '', ' ', '0x1A', '1e3', '0.5', '.5', '5.', '1.2.3', '- 1'
  ].freeze

  CASTS = [
    nil, 0, 5, -5, 5.5, -5.5, 5.999, 12, 2_147_483_647, 2_147_483_648, -2_147_483_648,
    -2_147_483_649, 1.005, 2.675, 123.456, 999.999, 1234.5678, 0.30000000000000004, 1.0e-05,
    1.2345649999, 99_999_999.995, *STRINGS, 'unplugged', 'charging', 'full', 'unknown', 'wifi',
    'mobile', 'offline', 'manual_event', 'bogus', '2', true, false, [1], { 'a' => 1 }
  ].freeze

  COLUMNS = %w[accuracy altitude_decimal course velocity battery_status connection trigger].freeze

  ARRAYS = [nil, [], ['home'], %w[home work], ['a', 1], [1.5], [true], [['x']], 'home'].freeze

  TIMESTAMPS = {
    true => [
      '2024-01-01T12:00:00Z', '2024-01-01T12:00:00.999Z', '2024-01-01T12:00:00+02:00',
      '2024-01-01T12:00:00+0200', '2024-01-01T12:00:00-07', '2024-01-01 12:00:00',
      '2024-01-01 12:00:00 +0200', '2024-01-01T12:00', '2024-01-01T12:00Z', '2024-01-01',
      '1969-12-31T23:59:59.5Z', 'Mon, 01 Jan 2024 12:00:00 GMT', '01 Jan 2024 12:00:00 +0100',
      'Tue, 31 Dec 2024 23:59:59 UT', '2026-02-30T12:00:00Z', '2023-02-29',
      '2024-04-31T00:00:00Z', '1788930000', '-2147483648', '2147483647', '2147483648', '007',
      1_788_930_000, 1_788_930_000_000, '2038-01-19T03:14:07Z', '2038-01-19T03:14:08Z',
      '1901-12-13T20:45:52Z', '1901-12-13T20:45:51Z', '2015-10-01T08:00:00-0700',
      '2024-01-01T12:00:00.000+00:00', nil, ''
    ],
    false => [
      'not-a-timestamp', 'Sat Aug 28 02:55:50 2021', '2024/01/01 12:00:00', '12:00',
      '1700000000.5', 1_700_000_000.5, 'Tue, 01 Jan 2024 12:00:00 GMT', '2024-01-01T24:00:00Z',
      '2024-01-01T12:00:60Z', '2024-01-01T12:00:00+25:00', '2024-01-01t12:00:00z', 'Jan 1 2024',
      'true', '-5', true
    ]
  }.freeze

  WKTS = [
    'POINT(13.4 52.5)', 'POINT(190.5 95)', 'POINT(-540 10)', 'POINT(540 -95.5)',
    'POINT(1.0e-05 52.5)', 'POINT(-0.0 51.5)', 'POINT(0 0)', 'POINT(0.0 0.0)', 'POINT(0.01 0.01)',
    'POINT(0.04 0.03)', 'POINT(.5 5.)', 'POINT(+13 52)', 'POINT(1E2 3)', 'POINT(abc 52)',
    'POINT(13.4 )', 'POINT(1 2 3)', 'POINT(-122.40530871 37.74430413)'
  ].freeze

  PAIRS = [
    [13.4, 52.5], [0, 0], [0.04, 0.03], ['0.01', '0.01'], [nil, 0], [0, nil], [45, 0.04],
    [0.0449, 0.0], [-0.0, 0.0449]
  ].freeze

  ACCEPTS = [
    [nil, nil], ['', nil], ['*/*', nil], ['application/json', nil],
    ['application/json; charset=utf-8', nil], ['application/json;q=0.9', nil],
    ['text/x-json', nil], ['text/html', nil], ['text/plain', nil], ['application/xml', nil],
    ['image/png', nil], ['Application/JSON', nil], ['application/json, text/plain, */*', nil],
    ['text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8', nil],
    ['application/json, text/plain', nil], [nil, 'json'], ['text/html', 'json'], [nil, 'xml'],
    [nil, 'png']
  ].freeze

  HOSTS = [
    ['localhost,::1,127.0.0.1', 'production', 'localhost:3000', nil, false],
    ['localhost,::1,127.0.0.1', 'production', '[::1]:3000', nil, false],
    ['localhost,::1,127.0.0.1', 'production', '127.0.0.1', nil, false],
    ['localhost,::1,127.0.0.1', 'production', 'evil.example', nil, false],
    ['localhost,::1,127.0.0.1', 'production', 'evil.example', nil, true],
    ['dawarich.example.com', 'production', 'dawarich.example.com', 'evil.example', false],
    ['dawarich.example.com', 'production', 'dawarich.example.com', 'a.example, dawarich.example.com', false],
    ['.example.com', 'production', 'maps.example.com:8443', nil, false],
    ['.example.com', 'production', 'example.com', nil, false],
    ['dawarich.example.com', 'production', 'DAWARICH.example.com', nil, false],
    ['dawarich.example.com', 'staging', nil, nil, false],
    ['', 'production', 'anything.example', nil, false],
    ['a, ', 'production', 'a', nil, false],
    ['localhost', 'development', '192.168.1.20:3000', nil, false],
    ['localhost', 'development', '[fe80::1]:3000', nil, false],
    ['localhost', 'development', 'box.test', nil, false],
    ['localhost', 'development', 'box.lan', nil, false],
    ['localhost', 'test', 'box.lan', nil, false]
  ].freeze

  FULL_FEATURE_PROPERTIES = {
    'timestamp' => ISO, 'battery_state' => 'charging', 'battery_level' => 0.555,
    'altitude' => 12.5, 'device_id' => 'phone', 'speed' => 3, 'wifi' => 'home',
    'horizontal_accuracy' => 5.7, 'vertical_accuracy' => '7', 'course' => 12.345678,
    'course_accuracy' => 1234.5, 'motion' => ['driving'], 'activity' => 'automotive',
    'action' => false
  }.freeze

  POINTS = [
    [true, {
      'api_key' => 'k', 'batch' => { 'id' => 1 },
      'locations' => [FEATURE.call([13.4, 52.5], FULL_FEATURE_PROPERTIES)]
    }],
    [true, { 'locations' => [
      FEATURE.call([0, 0], { 'timestamp' => 1_788_930_000 }),
      FEATURE.call([0.04, 0.03], { 'timestamp' => '1788930000' }),
      FEATURE.call(nil, { 'timestamp' => 1 }),
      FEATURE.call([13.4, 52.5], { 'timestamp' => '' }),
      { 'geometry' => { 'coordinates' => [1, 2] } },
      'scalar',
      FEATURE.call([13.4, 52.5], {})
    ] }],
    [true, { 'locations' => [FEATURE.call([13.4, 52.5], { 'timestamp' => '2026-02-30T12:00:00Z' })] }],
    [true, { 'locations' => [
      FEATURE.call(['13.40', '52.5'], { 'timestamp' => ISO, 'course' => '0x1A', 'battery_level' => '0.5' })
    ] }],
    [true, { 'locations' => [FEATURE.call([190.5, 95, 7], { 'timestamp' => ISO, 'departure_date' => ISO })] }],
    [true, { 'locations' => [
      FEATURE.call([13.4, nil, 52.5], { 'timestamp' => ISO, 'motion' => ['walking', nil] })
    ] }],
    [false, { 'locations' => { 'geometry' => { 'coordinates' => [1, 2] } } }],
    [false, { 'locations' => { '0' => FEATURE.call([13.4, 52.5], { 'timestamp' => 1 }) } }],
    [false, { 'locations' => [FEATURE.call('13,52', { 'timestamp' => ISO })] }],
    [false, {}]
  ].freeze

  OVERLAND = [
    [true, JSON.parse(Rails.root.join('spec/fixtures/files/overland/geodata.json').read)],
    [true, {
      'locations' => { 'geometry' => { 'coordinates' => [13.4, 52.5] }, 'properties' => { 'timestamp' => ISO } }
    }],
    [true, { '_json' => [1, 2] }],
    [true, { 'locations' => [
      { 'geometry' => { 'coordinates' => [0, 0] }, 'properties' => { 'timestamp' => 1 } },
      { 'geometry' => {}, 'properties' => { 'timestamp' => 1 } }
    ] }],
    [false, { 'locations' => [{ 'properties' => { 'timestamp' => 'bad' } }] }],
    [true, {}]
  ].freeze

  OWNTRACKS = [
    [true, {
      '_type' => 'location', 'lat' => 52.5, 'lon' => 13.4, 'tst' => 1_788_930_000, 'tid' => 'ab',
      'batt' => 85, 'bs' => 2, 'conn' => 'w', 't' => 'u', 'vel' => 50, 'alt' => 34, 'acc' => 10,
      'vac' => 3, 'SSID' => 'home', 'BSSID' => 'aa:bb', 'inregions' => ['home'], 'inrids' => ['r1'],
      'm' => 1, 'p' => 101.3, 'extra' => 'x'
    }],
    [true, {
      '_type' => 'location', 'lat' => '52.5', 'lon' => '13.4', 'tst' => '1788930000',
      'topic' => 'owntracks/u/d', 'vel' => 50, 'bs' => '9', 'conn' => 'x', 't' => 'z'
    }],
    [true, { '_type' => 'waypoint', 'lat' => 52.5, 'lon' => 13.4, 'tst' => 1 }],
    [true, { '_type' => 'transition', 'lat' => 52.5, 'lon' => 13.4, 'tst' => 1_788_930_000, 'event' => 'enter' }],
    [true, { '_type' => 'location', 'lat' => 52.5, 'lon' => 13.4 }],
    [true, { '_type' => 'location', 'lat' => 52.5, 'lon' => 13.4, 'tst' => 'abc', 'vel' => 0, 'topic' => 'x' }],
    [false, { 'lat' => 52.5, 'lon' => 13.4, 'tst' => 1_788_930_000, 'inregions' => 'home' }],
    [false, {
      'lat' => 52.5, 'lon' => 13.4, 'tst' => 1_788_930_000, 'inregions' => [{ 'a' => 1 }], 'batt' => true
    }]
  ].freeze

  TRACCAR = [
    [true, {
      'device_id' => 'phone', 'battery' => { 'level' => 0.8, 'is_charging' => false },
      'activity' => { 'type' => 'walking' },
      'location' => {
        'timestamp' => '2024-01-01T12:00:00.000Z', 'latitude' => 52.5, 'longitude' => 13.4,
        'accuracy' => 5, 'speed' => 1.5, 'altitude' => 30, 'is_moving' => true,
        'event' => 'motionchange'
      }
    }],
    [true, {
      'device_id' => 'phone',
      'location' => {
        'timestamp' => 1_788_930_000_000, 'is_moving' => false,
        'coords' => { 'latitude' => '52.5', 'longitude' => '13.4', 'speed' => 2 },
        'battery' => { 'level' => 0.5, 'is_charging' => 'false' },
        'activity' => { 'type' => 'still' }
      }
    }],
    [true, {
      'id' => 'osmand', 'lat' => '52.5', 'lon' => '13.4', 'timestamp' => '1788930000',
      'speed' => '10', 'batt' => '80', 'charge' => 'true', 'alarm' => 'sos', 'bearing' => '90'
    }],
    [true, { 'id' => 'osmand', 'lat' => '52.5', 'lon' => '13.4', 'timestamp' => '1788930000', 'charge' => '0' }],
    [true, { 'device_id' => 'x', 'location' => { 'timestamp' => ISO, 'latitude' => 95, 'longitude' => 13.4 } }],
    [true, { 'device_id' => 'x', 'location' => { 'latitude' => 52.5, 'longitude' => 13.4 } }],
    [false, {
      'device_id' => 'x',
      'location' => { 'timestamp' => 'not-a-date', 'latitude' => 52.5, 'longitude' => 13.4 }
    }],
    [true, {
      'device_id' => 'x',
      'location' => { 'timestamp' => '2026-02-30T12:00:00Z', 'latitude' => 52.5, 'longitude' => 13.4 }
    }],
    [true, { 'device_id' => 'x', 'location' => 'scalar', 'lat' => '1', 'lon' => '2', 'timestamp' => '5' }]
  ].freeze

  TRACCAR_PERMIT = [
    :device_id, :id, :lat, :lon, :timestamp, :accuracy, :altitude, :speed, :bearing, :batt,
    :charge, :alarm,
    { location: [
        :timestamp, :latitude, :longitude, :accuracy, :speed, :heading, :altitude, :is_moving,
        :odometer, :event, :manual,
        { coords: %i[latitude longitude accuracy speed heading altitude],
          battery: %i[level is_charging], activity: %i[type] }
      ],
      battery: %i[level is_charging], activity: %i[type] }
  ].freeze
end

RSpec.describe 'Phoenix fixture: ingestion building blocks as Rails computes them' do
  def run
    { 'ok' => plain(yield) }
  rescue Points::TimestampParser::InvalidTimestampError
    { 'error' => 'invalid_timestamp' }
  rescue StandardError => e
    { 'error' => e.class.name }
  end

  def plain(value)
    case value
    when DateTime, Time then value.to_i
    when BigDecimal then value.to_s('F')
    when ActionController::Parameters then plain(value.to_unsafe_h)
    when Hash then value.to_h { |key, item| [key.to_s, plain(item)] }
    when Array then value.map { plain(_1) }
    when Symbol then value.to_s
    else value
    end
  end

  def munged(input) = ActionDispatch::Request::Utils.normalize_encode_params(input.deep_dup)

  def exact_json(value, depth = 0)
    pad = '  ' * (depth + 1)
    case value
    when Hash
      return '{}' if value.empty?

      entries = value.map { |k, v| "#{pad}#{Oj.dump(k.to_s, mode: :strict)}: #{exact_json(v, depth + 1)}" }
      "{\n#{entries.join(",\n")}\n#{'  ' * depth}}"
    when Array
      return '[]' if value.empty?

      entries = value.map { |v| "#{pad}#{exact_json(v, depth + 1)}" }
      "[\n#{entries.join(",\n")}\n#{'  ' * depth}]"
    when Float
      value.to_s
    else
      Oj.dump(value, mode: :strict)
    end
  end

  def params_case(endpoint, own, input, filters, &build)
    permitted = ActionController::Parameters.new(munged(input)).permit(*filters)
    { 'endpoint' => endpoint, 'own' => own, 'input' => input, 'permit' => run { permitted },
      'payloads' => run { build.call(permitted) } }
  end

  def oracle_cases(endpoint, rows, filters, &build)
    rows.map { |own, input| params_case(endpoint, own, input, filters, &build) }
  end

  def request_for(accept, format)
    env = Rack::MockRequest.env_for("/api/v1/points#{"?format=#{format}" if format}", method: 'POST')
    env['HTTP_ACCEPT'] = accept if accept
    ActionDispatch::Request.new(env)
  end

  def host_case(hosts_env, rails_env, host, forwarded, xhr)
    list = hosts_env.split(',').map(&:strip)
    hosts = rails_env == 'development' ? ActionDispatch::HostAuthorization::ALLOWED_HOSTS_IN_DEVELOPMENT + list : list
    hosts = [] if rails_env == 'test'
    env = Rack::MockRequest.env_for('/api/v1/points', method: 'POST')
    if host
      env['HTTP_HOST'] = host
    else
      env.delete('HTTP_HOST')
    end
    env['HTTP_X_FORWARDED_HOST'] = forwarded if forwarded
    env['HTTP_X_REQUESTED_WITH'] = 'XMLHttpRequest' if xhr
    { 'application_hosts' => hosts_env, 'rails_env' => rails_env, 'host' => host,
      'forwarded' => forwarded, 'xhr' => xhr, 'result' => host_authorization_result(env, hosts) }
  end

  def host_authorization_result(env, hosts)
    return 'allowed' if hosts.empty?

    app = ->(_) { [200, {}, ['ok']] }
    status, headers, body = ActionDispatch::HostAuthorization.new(app, hosts).call(env)
    return 'allowed' if status == 200

    { 'status' => status, 'content-type' => headers['content-type'], 'body' => body.join }
  end

  def cast_cases
    IngestUnitsOracle::COLUMNS.product(IngestUnitsOracle::CASTS).map do |column, value|
      type = Point.type_for_attribute(column)
      not_own = value == true || value == false || value.is_a?(Array) || value.is_a?(Hash) ||
                (value.is_a?(Integer) && value.abs >= 1000)
      { 'column' => column, 'input' => value, 'own' => !not_own,
        'result' => run { ActiveModel::Type::SerializeCastValue.serialize(type, type.cast(value)) } }
    end + IngestUnitsOracle::ARRAYS.map do |value|
      type = Point.type_for_attribute('inrids')
      is_own = value.nil? || (value.is_a?(Array) && value.all? { _1.is_a?(String) })
      { 'column' => 'inrids', 'input' => value, 'own' => is_own, 'result' => run { type.cast(value) } }
    end
  end

  def timestamp_cases
    IngestUnitsOracle::TIMESTAMPS.flat_map do |own, values|
      values.map do |value|
        { 'input' => value, 'own' => own, 'points' => run { Points::TimestampParser.call(value) },
          'traccar' => run { Traccar::Params.allocate.send(:parse_timestamp, value) } }
      end
    end
  end

  def wkt_cases(lonlat)
    IngestUnitsOracle::WKTS.map do |wkt|
      geo = lonlat.cast(wkt)
      { 'input' => wkt, 'point' => geo && [geo.x, geo.y], 'null_island' => Points::NullIsland.lonlat?(wkt),
        'dedup_key' => Point.dedup_key({ lonlat: wkt, timestamp: 1, user_id: 1 }) }
    end
  end

  def pair_cases
    IngestUnitsOracle::PAIRS.map do |lon, lat|
      { 'lon' => lon, 'lat' => lat, 'null_island' => Points::NullIsland.coordinates?(lon, lat) }
    end
  end

  def accept_cases
    IngestUnitsOracle::ACCEPTS.map do |accept, format|
      request = request_for(accept, format)
      refs = request.formats.map(&:ref)
      { 'accept' => accept, 'format' => format, 'first' => refs.first&.to_s,
        'vary' => request.should_apply_vary_header?, 'head' => (Mime[refs.first] || Mime[:html]).to_s }
    end
  end

  def param_cases(geo_filters, owntracks_filters)
    oracle_cases('points', IngestUnitsOracle::POINTS, geo_filters) { |p| Points::Params.new(p.to_h, 1).call } +
      oracle_cases('overland', IngestUnitsOracle::OVERLAND, geo_filters) { |p| Overland::Params.new(p).call } +
      oracle_cases('owntracks', IngestUnitsOracle::OWNTRACKS, owntracks_filters) { |p| OwnTracks::Params.new(p).call } +
      oracle_cases('traccar', IngestUnitsOracle::TRACCAR, IngestUnitsOracle::TRACCAR_PERMIT) { |p| Traccar::Params.new(p).call }
  end

  it 'writes app-phoenix/test/fixtures/ingest/units.json' do
    lonlat = Point.type_for_attribute('lonlat')
    geo_filters = [{ locations: [:type, { geometry: {}, properties: {} }], batch: {} }]
    owntracks_filters = [*Api::V1::Owntracks::PointsController::OWNTRACKS_FIELDS, { inregions: [], inrids: [] }]

    fixture = {
      'strings' => IngestUnitsOracle::STRINGS.map do |s|
        { 'input' => s, 'to_i' => s.to_i, 'to_d' => s.to_d.to_s('F') }
      end,
      'casts' => cast_cases,
      'timestamps' => timestamp_cases,
      'wkts' => wkt_cases(lonlat),
      'pairs' => pair_cases,
      'accepts' => accept_cases,
      'hosts' => IngestUnitsOracle::HOSTS.map { |row| host_case(*row) },
      'params' => param_cases(geo_filters, owntracks_filters)
    }

    path = Rails.root.join('app-phoenix/test/fixtures/ingest/units.json')
    FileUtils.mkdir_p(path.dirname)
    File.write(path, "#{exact_json(fixture)}\n")
  end
end
