# frozen_string_literal: true

require 'rails_helper'
require_relative 'fixture_recording'

module IngestGoldenOracle
  FEATURE = lambda do |lon, lat, ts, props = {}|
    { type: 'Feature', geometry: { type: 'Point', coordinates: [lon, lat] },
      properties: { timestamp: ts }.merge(props) }
  end
  PASSWORD = 'phoenix-a3-golden-password'
  TABLES = %w[users families family_memberships point_sources points].freeze
  ROWS_SQL = <<~SQL.squish
    SELECT p.id, encode(ST_AsBinary(p.lonlat), 'hex') AS lonlat, p.timestamp, p.altitude, p.altitude_decimal::text AS altitude_decimal,
      p.accuracy, p.vertical_accuracy, p.battery, p.battery_status, p.velocity, p.tracker_id, p.ssid, p.bssid, p.topic, p.ping,
      p.connection, p.trigger, p.course::text AS course, p.course_accuracy::text AS course_accuracy, p.inrids::text AS inrids,
      p.in_regions::text AS in_regions, p.raw_data::text AS raw_data, p.motion_data::text AS motion_data, s.digest AS source_digest,
      p.raw_data_archived, p.raw_data_archive_id, p.anomaly, p.lock_version, p.created_at = p.updated_at AS fresh,
      p.geodata::text AS geodata, p.import_id, p.track_id, p.visit_id, p.country_id, p.city, p.country_name,
      p.reverse_geocoded_at::text AS reverse_geocoded_at
    FROM points p LEFT JOIN point_sources s ON s.id = p.source_id WHERE p.user_id = $1 ORDER BY p.id
  SQL
  MULTIPART_PARTS = %w[id=osmand lat=52.5 lon=13.4 timestamp=1790000000].map do |pair|
    name, value = pair.split('=')
    "--X\r\nContent-Disposition: form-data; name=\"#{name}\"\r\n\r\n#{value}\r\n"
  end
  MULTIPART = MULTIPART_PARTS.join.concat("--X--\r\n")
  OT = '/api/v1/owntracks/points'
  OL = '/api/v1/overland/batches'
  TC = '/api/v1/traccar/points'
  CASES = [
    { name: 'points_full',
      body: { locations: [FEATURE.call(13.4, 52.52, '2026-09-28T11:00:00Z', battery_state: 'charging',
                                        battery_level: 0.555, altitude: 12.5, device_id: 'phone', speed: 3.4,
                                        wifi: 'home', horizontal_accuracy: 5.7, vertical_accuracy: '7',
                                        course: 12.345678, course_accuracy: 2.675, motion: ['driving'],
                                        activity: 'automotive', departure_date: '2026-09-28T10:00:00Z'),
                          FEATURE.call(13.41, 52.53, 1_790_000_000)] } },
    { name: 'points_query_key_accept_json', auth: :query, headers: { 'Accept' => 'application/json' },
      body: { locations: [FEATURE.call(13.4, 52.5, '1790000000')] } },
    { name: 'points_formats',
      body: { locations: ['2024-01-01 12:00:00', '2024-01-01 12:00:00 +0200', 'Mon, 01 Jan 2024 12:00:00 GMT',
                          '2024-01-02', '2015-10-01T08:00:00-0700'].each_with_index.map do |ts, i|
                            FEATURE.call(13.4 + (i / 100.0), 52.5, ts)
                          end } },
    { name: 'points_invalid_timestamp',
      body: { locations: [FEATURE.call(13.4, 52.5, '2024-01-01T12:00:00Z'),
                          FEATURE.call(13.5, 52.5, '2026-02-30T12:00:00Z')] } },
    { name: 'points_out_of_range', body: { locations: [FEATURE.call(13.4, 52.5, '2147483648')] } },
    { name: 'points_skip_rules',
      body: { locations: [FEATURE.call(0, 0, 1_790_000_000), FEATURE.call(0.04, 0.03, 1_790_000_001),
                          { type: 'Feature', properties: { timestamp: 1_790_000_002 } },
                          FEATURE.call(13.4, 52.5, ''), { type: 'Feature', geometry: { coordinates: [1, 2] } },
                          FEATURE.call(13.4, 52.5, 1_790_000_003)] } },
    { name: 'points_duplicates',
      raw: '{"locations":[{"geometry":{"coordinates":["13.40","52.5"]},"properties":{"timestamp":1790000000}},' \
           '{"geometry":{"coordinates":[13.4,52.5]},"properties":{"timestamp":1790000000}}]}' },
    { name: 'points_conflict', setup: :conflict,
      body: { locations: [FEATURE.call(13.4, 52.5, 1_788_930_000, altitude: 99),
                          FEATURE.call(13.5, 52.5, 1_788_930_060)] } },
    { name: 'points_casts',
      body: { locations: [FEATURE.call(13.4, 52.5, 1_790_000_000, horizontal_accuracy: 5.7,
                                        altitude: '123.456', course: 1234.5, course_accuracy: '12.3456789',
                                        battery_level: '0.5', battery_state: 'bogus', speed: 3,
                                        wifi: 12, device_id: 42, vertical_accuracy: '7x')] } },
    { name: 'points_wrapped_coordinates',
      body: { locations: [FEATURE.call(190.5, 95, 1_790_000_000), FEATURE.call(-540, 10, 1_790_000_001)] } },
    { name: 'points_float_text',
      raw: '{"locations":[{"geometry":{"coordinates":[0.00001,52.5]},"properties":{"timestamp":1790000000,' \
           '"altitude":0.30000000000000004,"speed":1e-05}}]}' },
    { name: 'points_empty', body: { locations: [] } },
    { name: 'points_slices',
      body: { locations: (1..1001).map { |i| FEATURE.call(10 + ((1002 - i) / 10_000.0), 50, 1_790_000_000 + i) } } },
    { name: 'points_munged_nils',
      raw: '{"locations":[{"geometry":{"coordinates":[13.4,null,52.5]},"properties":{"timestamp":1790000000,' \
           '"motion":["walking",null]}}]}' },
    { name: 'points_session_cookie', setup: :session, body: { locations: [FEATURE.call(13.4, 52.5, 1_790_000_000)] },
      ignore: ['set-cookie'] },
    { name: 'overland_geodata', path: OL, auth: :query,
      raw: Rails.root.join('spec/fixtures/files/overland/geodata.json').read },
    { name: 'overland_single_hash', path: OL,
      body: { locations: { geometry: { coordinates: [13.4, 52.5] },
                            properties: { timestamp: '2026-09-28T11:00:00Z' } } } },
    { name: 'overland_array_body', path: OL, raw: '[{"geometry":{"coordinates":[13.4,52.5]}}]' },
    { name: 'overland_invalid_timestamp', path: OL, body: { locations: [FEATURE.call(13.4, 52.5, '2023-02-29')] } },
    { name: 'overland_null_island_text', path: OL,
      raw: '{"locations":[{"geometry":{"coordinates":[0,0]},"properties":{"timestamp":1}},' \
           '{"geometry":{"coordinates":[0.0,0.0]},"properties":{"timestamp":2}},' \
           '{"geometry":{"coordinates":[0.00001,0]},"properties":{"timestamp":3}}]}' },
    { name: 'owntracks_http', path: OT, auth: :query,
      body: { _type: 'location', lat: 52.5, lon: 13.4, tst: 1_790_000_000, tid: 'ab', batt: 85, bs: 2, conn: 'w',
              t: 'u', vel: 50, alt: 34, acc: 10, vac: 3, SSID: 'home', BSSID: 'aa:bb', inregions: ['home'],
              inrids: ['r1'], m: 1, p: 101.3 } },
    { name: 'owntracks_topic', path: OT, auth: :query,
      body: { _type: 'location', lat: '52.5', lon: '13.4', tst: '1790000000', topic: 'owntracks/u/d', vel: 50 } },
    { name: 'owntracks_waypoint', path: OT, auth: :query, body: { _type: 'waypoint', lat: 52.5, lon: 13.4, tst: 1 } },
    { name: 'owntracks_transition', path: OT, auth: :query,
      body: { _type: 'transition', lat: 52.5, lon: 13.4, tst: 1_790_000_000, event: 'enter' } },
    { name: 'owntracks_tst_garbage', path: OT, auth: :query,
      body: { _type: 'location', lat: 52.5, lon: 13.4, tst: 'abc', topic: 'x' } },
    { name: 'owntracks_friends', setup: :family, path: OT, auth: :query,
      body: { _type: 'location', lat: 52.5, lon: 13.4, tst: 1_790_000_000 } },
    { name: 'owntracks_friends_failure', setup: :family, path: OT, auth: :query,
      body: { _type: 'location', lat: 52.5, lon: 13.4, tst: 1_790_000_000 },
      rails_stub: :friends_failure, phoenix_fault: ['ALTER TABLE family_memberships RENAME TO family_memberships_a3'],
      expect: :replay },
    { name: 'traccar_flat', path: TC,
      body: { device_id: 'phone', battery: { level: 0.8, is_charging: false }, activity: { type: 'walking' },
              location: { timestamp: '2026-09-28T11:00:00.000Z', latitude: 52.5, longitude: 13.4, accuracy: 5,
                          speed: 1.5, altitude: 30, is_moving: true, event: 'motionchange' } } },
    { name: 'traccar_nested', path: TC,
      body: { device_id: 'phone', location: { timestamp: 1_790_000_000_000, is_moving: false,
                                               activity: { type: 'still' },
                                               coords: { latitude: '52.5', longitude: '13.4', speed: 2 },
                                               battery: { level: 0.5, is_charging: 'false' } } } },
    { name: 'traccar_form', path: TC, auth: :query,
      form: 'id=osmand&lat=52.5&lon=13.4&timestamp=1790000000&speed=10&batt=80&charge=true&alarm=sos' },
    { name: 'traccar_bad_latitude', path: TC,
      body: { device_id: 'x', location: { timestamp: '2026-09-28T11:00:00Z', latitude: 95, longitude: 13.4 } } },
    { name: 'auth_missing', auth: :none, body: { locations: [] } },
    { name: 'auth_blank_param_beats_bearer', path: '/api/v1/points?api_key=', body: { locations: [] } },
    { name: 'auth_unknown_accept_json', auth: :unknown, headers: { 'Accept' => 'application/json' },
      body: { locations: [] } },
    { name: 'auth_deleted', setup: :deleted, body: { locations: [] } },
    { name: 'pending_payment', setup: :pending, headers: { 'Accept' => 'application/json' }, body: { locations: [] } },
    { name: 'inactive', setup: :inactive, path: OT, auth: :query, body: { lat: 1, lon: 1, tst: 1 } },
    { name: 'expired', setup: :expired, path: TC, body: {} },
    { name: 'request_id_valid', headers: { 'X-Request-Id' => 'phoenix-a3-req_1@golden' }, body: { locations: [] } },
    { name: 'request_id_sanitized', headers: { 'X-Request-Id' => "bad id/<x>#{'a' * 300}" }, body: { locations: [] } },
    { name: 'conditional_if_none_match', path: OL,
      headers: { 'If-None-Match' => %(W/"#{Digest::SHA256.hexdigest('{"result":"ok"}')[0, 32]}") },
      body: { locations: [FEATURE.call(13.4, 52.5, 1_790_000_000)] } },
    { name: 'replay_json_comment', raw: '{"locations":[] /* c */}', expect: :replay },
    { name: 'replay_heuristic_timestamp', body: { locations: [FEATURE.call(13.4, 52.5, 'Sat Aug 28 02:55:50 2021')] },
      expect: :replay },
    { name: 'replay_coordinate_text', body: { locations: [FEATURE.call('abc', 52.5, 1_790_000_000)] },
      expect: :replay },
    { name: 'replay_client_header', headers: { 'X-Dawarich-Client' => 'ios' }, body: { locations: [] },
      expect: :replay },
    { name: 'replay_remember_cookie', setup: :remember, body: { locations: [] }, expect: :replay },
    { name: 'replay_multipart', path: TC, auth: :query, multipart: true, expect: :replay },
    { name: 'replay_nested_form', auth: :query, form: 'locations[][geometry][coordinates][]=13.4', expect: :replay },
    { name: 'replay_boolean_battery',
      body: { locations: [FEATURE.call(13.4, 52.5, 1_790_000_000, battery_level: true)] }, expect: :replay },
    { name: 'replay_accept_png', auth: :none, headers: { 'Accept' => 'image/png' }, body: { locations: [] },
      expect: :replay }
  ].freeze
  FAULT = [
    'CREATE FUNCTION a3_fault() RETURNS trigger LANGUAGE plpgsql AS $$ BEGIN IF NEW.timestamp = 1790001001 THEN ' \
    "RAISE EXCEPTION 'a3 fault'; END IF; RETURN NEW; END $$",
    'CREATE TRIGGER a3_fault BEFORE INSERT ON points FOR EACH ROW EXECUTE FUNCTION a3_fault()'
  ].freeze
  SLICE_FAULT = { name: 'points_slice2_fault', fault: FAULT,
                  body: { locations: (1..1001).map do |i|
                    FEATURE.call(10 + (i / 10_000.0), 50, 1_790_000_000 + i)
                  end } }.freeze
  EXPECTED_NAMES = (CASES.map { _1[:name] } + [SLICE_FAULT[:name]]).sort.freeze

  def self.results
    @results ||= []
  end
end

RSpec.describe 'Phoenix fixture: golden ingestion requests', type: :request do
  let(:fixture_models) { [User, Family, Family::Membership, Point, PointSource] }
  include FixtureRecording::DeterministicInputs
  after(:all) do
    results = IngestGoldenOracle.results
    missing = IngestGoldenOracle::EXPECTED_NAMES - results.map { _1['name'] }
    raise "golden generator incomplete, missing cases: #{missing.join(', ')}" if missing.any?

    path = Rails.root.join('app-phoenix/test/fixtures/ingest/golden.json')
    fixture = { 'rows_sql' => IngestGoldenOracle::ROWS_SQL,
                'cases' => results.reject { _1['name'].start_with?('closure_') }.sort_by { _1['name'] },
                'closure_cases' => results.select { _1['name'].start_with?('closure_') }.sort_by { _1['name'] } }
    encoded = "#{Oj.dump(fixture, mode: :strict, float_precision: 0, indent: 2)}\n"
    File.write(path, encoded) if ENV['WRITE_PHOENIX_FIXTURES'] == '1'

    written = JSON.parse(encoded)
    float_case = written['cases'].find { _1['name'] == 'points_float_text' }
    broadcast = float_case['commands'].find { _1['kind'] == 'points.live_broadcast' }
    altitude = broadcast['payload']['payloads'][0]['altitude']
    unless altitude.to_s == '0.30000000000000004'
      raise "points_float_text's recorded commands lost float precision on write: altitude=#{altitude.inspect}"
    end
  end

  IngestGoldenOracle::CASES.each do |kase|
    it(kase[:name]) {
      IngestGoldenOracle.results << record(
        kase.reverse_merge(setup: :user, path: '/api/v1/points', auth: :bearer, expect: :own)
      )
      capture_closure_ingest! if kase[:name] == 'points_empty'
    }
  end

  context 'when the second slice fails (Rails commits each slice on its own)' do
    self.use_transactional_tests = false

    around do |example|
      sources = PointSource.maximum(:id).to_i
      example.run
    ensure
      ActiveRecord::Base.connection.execute('DROP TRIGGER IF EXISTS a3_fault ON points')
      ActiveRecord::Base.connection.execute('DROP FUNCTION IF EXISTS a3_fault()')
      ids = User.where(api_key: "phoenix-a3-golden-key-#{IngestGoldenOracle::SLICE_FAULT[:name]}").pluck(:id)
      Point.where(user_id: ids).delete_all
      PointSource.where('id > ?', sources).delete_all
      User.where(id: ids).delete_all
    end

    it(IngestGoldenOracle::SLICE_FAULT[:name]) do
      IngestGoldenOracle.results << record(
        IngestGoldenOracle::SLICE_FAULT.reverse_merge(setup: :user, path: '/api/v1/points', auth: :bearer, expect: :own)
      )
    end
  end

  def capture_closure_ingest!
    cases = [
      { name: 'closure_overland_boolean_device', path: IngestGoldenOracle::OL,
        body: { locations: [IngestGoldenOracle::FEATURE.call(13.4, 52.5, 1_790_000_000, device_id: true)] } },
      { name: 'closure_overland_array_device', path: IngestGoldenOracle::OL,
        body: { locations: [IngestGoldenOracle::FEATURE.call(13.4, 52.5, 1_790_000_000, device_id: [1, true])] } },
      { name: 'closure_overland_integer_boolean', path: IngestGoldenOracle::OL,
        body: { locations: [IngestGoldenOracle::FEATURE.call(13.4, 52.5, 1_790_000_000, altitude: true)] } },
      { name: 'closure_overland_integer_container', path: IngestGoldenOracle::OL,
        body: { locations: [IngestGoldenOracle::FEATURE.call(13.4, 52.5, 1_790_000_000, altitude: {})] } },
      { name: 'closure_points_weekday',
        body: { locations: [IngestGoldenOracle::FEATURE.call(13.4, 52.5, 'Sat Aug 28 02:55:50 2021')] } },
      { name: 'closure_owntracks_boolean_device', path: IngestGoldenOracle::OT,
        body: { lat: 52.5, lon: 13.4, tst: 1_790_000_000, tid: true, inregions: [1, true] } },
      { name: 'closure_traccar_boolean_device', path: IngestGoldenOracle::TC,
        body: { device_id: false, location: { timestamp: '2026-09-28T11:00Z', latitude: 52.5, longitude: 13.4 } } },
      { name: 'closure_owntracks_friends_failure', setup: :family, path: IngestGoldenOracle::OT,
        body: { _type: 'location', lat: 52.5, lon: 13.4, tst: 1_790_000_000 },
        rails_stub: :friends_failure,
        phoenix_fault: ['ALTER TABLE family_memberships RENAME TO family_memberships_a3'] }
    ]
    cases.each do |kase|
      result = nil
      ActiveRecord::Base.transaction(requires_new: true) do
        result = record(kase.reverse_merge(setup: :user, path: '/api/v1/points', auth: :bearer, expect: :own))
        raise ActiveRecord::Rollback
      end
      IngestGoldenOracle.results << result
    end
  end

  def sql_rows(sql) = ActiveRecord::Base.connection.select_values(sql).map { JSON.parse(_1) }

  def user_for(kase)
    password = IngestGoldenOracle::PASSWORD
    user = create(:user, password:, password_confirmation: password)
    user.update_columns(api_key: "phoenix-a3-golden-key-#{kase[:name]}",
                        settings: user.settings.merge('live_map_enabled' => true, 'timezone' => 'Europe/Berlin'))
    case kase[:setup]
    when :pending then user.update_columns(status: User.statuses[:pending_payment])
    when :inactive then user.update_columns(status: User.statuses[:inactive], active_until: Time.utc(2099))
    when :expired then user.update_columns(status: User.statuses[:active], active_until: Time.utc(2001))
    when :deleted then user.update_columns(deleted_at: Time.current)
    when :family then family!(user)
    when :conflict
      Point.insert_all([{ user_id: user.id, timestamp: 1_788_930_000, lonlat: 'POINT(13.4 52.5)',
                          raw_data: { 'old' => true }, raw_data_archived: true,
                          created_at: Time.utc(2001), updated_at: Time.utc(2001) }])
      user.update_columns(points_count: 1)
    end
    user
  end

  def family!(user)
    family = Family.create!(name: 'Golden', creator: user)
    Family::Membership.create!(family:, user:, role: :owner)
    share = ->(expires) { { 'family' => { 'location_sharing' => { 'enabled' => true, 'expires_at' => expires } } } }
    user.update_columns(settings: user.settings.merge(share.call(nil)))
    [[share.call('2099-01-01T00:00:00+00:00'), true, false], [share.call(nil), false, false],
     [{ 'family' => { 'location_sharing' => { 'enabled' => false } } }, true, false],
     [share.call('2001-01-01T00:00:00Z'), true, false],
     [share.call(nil), true, true]].each_with_index do |(settings, point, deleted), i|
      member = create(:user)
      member.update_columns(api_key: "phoenix-a3-golden-member-#{i}", settings: member.settings.merge(settings))
      Family::Membership.create!(family:, user: member, role: :member)
      if point
        Point.insert_all([{ user_id: member.id, timestamp: 1_788_930_000 + i, lonlat: "POINT(13.4#{i} 52.5)",
                            battery: 55, battery_status: 5, created_at: Time.current, updated_at: Time.current }])
      end
      member.update_columns(deleted_at: Time.current) if deleted
    end
  end

  def cookie_for(setup, user)
    return unless %i[session remember].include?(setup)

    password = IngestGoldenOracle::PASSWORD
    post user_session_path, params: { user: { email: user.email, password:, remember_me: '1' } }
    name = setup == :session ? '_dawarich_session' : 'remember_user_token'
    value = cookies[name]
    reset!
    "#{name}=#{value}"
  end

  def body_for(kase)
    return [IngestGoldenOracle::MULTIPART, 'multipart/form-data; boundary=X'] if kase[:multipart]
    return [kase[:form], 'application/x-www-form-urlencoded'] if kase[:form]
    return [kase[:raw], 'application/json'] if kase[:raw]

    [kase[:body].to_json, 'application/json']
  end

  def spy!
    @backfill_cycle = 0
    allow(SecureRandom).to receive(:uuid).and_wrap_original do |original|
      if caller_locations.any? { _1.path.end_with?('/tracks/backfill_state.rb') }
        @backfill_cycle += 1
        format('11530000-0000-4000-8000-%012d', @backfill_cycle)
      else
        original.call
      end
    end
    calls = []
    allow(Points::TileEpoch).to receive(:bump).and_wrap_original do |m, uid, **kw|
      calls << ['points.tile_epoch', { 'user_id' => uid, 'timestamps' => kw[:timestamps].map(&:to_i) }]
      m.call(uid, **kw)
    end
    allow(Points::AnomalyFilterJob).to receive(:perform_later).and_wrap_original do |m, *a|
      calls << ['points.anomaly_filter', { 'user_id' => a[0], 'start_at' => a[1], 'end_at' => a[2] }]
      m.call(*a)
    end
    { Tracks::RealtimeDebouncer => 'tracks.realtime',
      Visits::RealtimeDebouncer => 'visits.realtime' }.each do |klass, kind|
      allow(klass).to(receive(:new).and_wrap_original { |m, uid| calls << [kind, { 'user_id' => uid }] && m.call(uid) })
    end
    allow(Tracks::BackfillScheduler).to receive(:new).and_wrap_original do |m, uid, ts|
      calls << ['tracks.backfill', { 'user_id' => uid, 'timestamps' => ts.compact.minmax }]
      m.call(uid, ts)
    end
    allow(Points::LiveBroadcaster).to receive(:new).and_wrap_original do |m, uid, up, pl|
      payloads = pl.map do |p|
        p.slice(:battery, :altitude, :velocity).merge(timestamp: p[:timestamp].to_i).compact.stringify_keys
      end
      calls << ['points.live_broadcast', { 'user_id' => uid, 'broadcast_id' => SecureRandom.uuid,
                                           'upserted' => up.map { _1.except('xmax') }, 'payloads' => payloads }]
      m.call(uid, up, pl)
    end
    calls
  end

  def years(timestamps) = timestamps.map { Time.at(_1).utc.year.clamp(1970, 2100) }.uniq.sort

  def normalizer(user, setup_ids)
    fresh = (Point.where(user_id: user.id).order(:id).pluck(:id) - setup_ids).each_with_index.to_h do |id, i|
      [id, "new:#{i}"]
    end
    lambda do |text|
      text.gsub(/"id":(\d+)/) do
        fresh.key?(Regexp.last_match(1).to_i) ? %("id":"#{fresh[Regexp.last_match(1).to_i]}") : Regexp.last_match(0)
      end
    end
  end

  def effects(user)
    iso = lambda { |v|
      if v.is_a?(String) && v.match?(/\A\d{4}-\d{2}-\d{2}T/)
        [Time.iso8601(v).utc_offset,
         ((Time.iso8601(v) - Time.current) / 60).round]
      else
        v
      end
    }
    jobs = enqueued_jobs.map do |job|
      args = JSON.parse(job[:args].to_json).map { |a| a.is_a?(Hash) ? a.transform_values(&iso) : a }
      [job[:job].name, args, job[:queue], job[:at] && (job[:at] - Time.current.to_f).round]
    end
    keys = Sidekiq.redis { |r| r.keys('*') }
                  .grep(/\A(track_realtime|track_backfill|visit_realtime|points:tile_epoch):/).sort
    streams = [PointsChannel.broadcasting_for(user)] +
              (user.family ? [FamilyLocationsChannel.broadcasting_for(user.family)] : [])
    { 'jobs' => jobs.sort_by(&:to_s), 'keys' => keys, 'phoenix' => phoenix_effects, 'cable' => streams.map do
      ActionCable.server.pubsub.broadcasts(_1)
    end }
  end

  def phoenix_effects
    connection = ActiveRecord::Base.connection
    PhoenixTables::PHOENIX_STATE_TABLES.index_with do |table|
      scope = if table == 'once_claims'
                " WHERE key ~ '^(track_realtime|track_backfill|visit_realtime|points:tile_epoch):'"
              else
                ''
              end
      connection.select_all(
        'SELECT *, round(extract(epoch FROM expires_at - statement_timestamp()) / 60) AS ttl_minutes ' \
        "FROM phoenix.#{table}#{scope}"
      ).to_a.map { _1.except('expires_at', 'revision') }.sort_by(&:to_s)
    end
  end

  def clear_phoenix_effects!
    FixtureCleanup.delete!(PhoenixTables::PHOENIX_STATE_TABLES.map { "phoenix.#{_1}" })
  end

  def reverse_outbox_equivalent!(user, calls, name)
    before = effects(user)
    clear_enqueued_jobs
    Sidekiq.redis(&:flushdb)
    clear_phoenix_effects!
    ActionCable.server.pubsub.clear
    phoenix_tables!
    calls.each do |kind, payload|
      json = Oj.dump(payload, mode: :strict, float_precision: 0)
      expect(json).to include('0.30000000000000004') if name == 'points_float_text' && kind == 'points.live_broadcast'
      ActiveRecord::Base.connection.execute(
        ActiveRecord::Base.sanitize_sql_array(
          ['INSERT INTO phoenix.rails_commands (kind, payload) VALUES (?, ?::jsonb)', kind, json]
        )
      )
    end
    @backfill_cycle = 0
    Time.use_zone(user.timezone) { RailsCommands::Poller.drain_once }
    expect(effects(user)).to eq(before)
  end

  def record(kase)
    Sidekiq.redis(&:flushdb)
    clear_phoenix_effects!
    ActionCable.server.pubsub.clear
    clear_enqueued_jobs
    user = user_for(kase)
    headers = { 'Host' => 'localhost' }.merge(kase[:headers] || {})
    cookie = cookie_for(kase[:setup], user)
    headers['Cookie'] = cookie if cookie
    headers['Authorization'] = "Bearer #{user.api_key}" if kase[:auth] == :bearer
    headers['Authorization'] = 'Bearer phoenix-a3-golden-unknown' if kase[:auth] == :unknown
    path = kase[:path]
    if kase[:auth] == :query
      separator = kase[:path].include?('?') ? '&' : '?'
      path = "#{path}#{separator}api_key=#{user.api_key}"
    end
    body, type = body_for(kase)
    headers['Content-Type'] = type
    setup = IngestGoldenOracle::TABLES.index_with do |table|
      sql_rows("SELECT row_to_json(t)::text FROM #{table} t ORDER BY id")
    end
    setup_ids = setup['points'].select { _1['user_id'] == user.id }.pluck('id')
    calls = spy!
    Array(kase[:fault]).each { ActiveRecord::Base.connection.execute(_1) }
    if kase[:rails_stub] == :friends_failure
      allow(Families::Locations).to receive(:new).and_raise(ActiveRecord::StatementInvalid, 'a3 forced friends failure')
    end

    post path, params: body, headers: headers

    result = { 'name' => kase[:name], 'expect' => kase[:expect].to_s, 'ignore' => kase[:ignore] || [],
               'user_id' => user.id, 'setup' => setup, 'setup_point_ids' => setup_ids,
               'fault' => Array(kase[:fault]), 'phoenix_fault' => Array(kase[:phoenix_fault]),
               'request' => { 'target' => path, 'headers' => headers.to_a, 'body' => body } }
    if kase[:expect] == :replay
      return result.merge('response' => { 'status' => response.status, 'body' => response.body })
    end

    ids = normalizer(user, setup_ids)
    commands = calls.map do |kind, payload|
      next { 'kind' => kind, 'years' => years(payload['timestamps']) } if kind == 'points.tile_epoch'

      dumped = Oj.dump(payload.except('broadcast_id'), mode: :strict, float_precision: 0)
      { 'kind' => kind, 'payload' => JSON.parse(ids.call(dumped)) }
    end
    rows_sql = IngestGoldenOracle::ROWS_SQL.sub('$1', user.id.to_s)
    rows = JSON.parse(ids.call(ActiveRecord::Base.connection.exec_query(rows_sql).to_a.to_json))
    count = ActiveRecord::Base.connection.select_value("SELECT points_count FROM users WHERE id = #{user.id}")
    response_headers = response.headers.to_h.transform_keys(&:downcase).except('date', 'content-length')
    snapshot = result.merge(
      'response' => { 'status' => response.status, 'headers' => response_headers, 'body' => ids.call(response.body),
                      'content_length' => response.body.bytesize },
      'rows' => rows, 'points_count' => count, 'commands' => commands
    )
    reverse_outbox_equivalent!(user, calls, kase[:name]) if calls.any?
    snapshot
  end
end
