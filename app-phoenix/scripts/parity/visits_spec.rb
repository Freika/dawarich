# frozen_string_literal: true

require 'rails_helper'
require_relative 'wave5b_fixture_support'

RSpec.describe 'Phoenix fixture: Rails visit detection' do
  include Wave5bFixtureSupport

  let!(:http) { record_http! }
  let!(:months) { capture_months! }
  let!(:stages) { capture_stages! }

  def capture_months!
    captured = []
    allow(Rails.cache).to receive(:delete).and_wrap_original do |original, key, *rest|
      captured << key[2] if key.is_a?(Array) && key.first == 'timeline_month_summary'
      original.call(key, *rest)
    end
    captured
  end

  def capture_stages!
    captured = Hash.new { |hash, key| hash[key] = [] }
    stage_classes = { 'fragments' => Visits::Detection::DwellSweep, 'bridged' => Visits::Detection::GapBridger,
                      'reconciled' => Visits::Detection::MovementReconciler,
                      'stays' => Visits::Detection::StayAssembler }
    stage_classes.each do |name, klass|
      allow_any_instance_of(klass).to receive(:call).and_wrap_original do |original, *args|
        original.call(*args).tap { |output| captured[name] << plain(output) }
      end
    end
    allow_any_instance_of(Visits::Detection::Persister).to receive(:call).and_wrap_original do |original, stays, **kw|
      captured['attributed'] << plain(stays)
      original.call(stays, **kw)
    end
    captured
  end

  def visit_effects
    reverse = enqueued(ReverseGeocodingJob).select { |args| args.first == 'place' }.map(&:second)
    { 'visit_months' => months.uniq.sort,
      'orphan_place_ids' => enqueued(Places::DeleteIfOrphanJob).map(&:first).uniq.sort,
      'reverse_geocode_place_ids' => reverse, 'place_name_fetch_ids' => enqueued(Places::NameFetchingJob).map(&:first) }
  end

  def visits_for(user)
    rows(<<~SQL.squish, user.id).map { |row| row.merge('deleted_at' => clock_state(row['deleted_at'])) }
      SELECT row_to_json(x)::text FROM (
        SELECT id, user_id, area_id, place_id, floor(extract(epoch FROM started_at))::bigint AS started_at,
               floor(extract(epoch FROM ended_at))::bigint AS ended_at, duration, name, status, confidence,
               confidence_breakdown::text AS confidence_breakdown, detection_version, demo, import_id,
               deleted_at::text AS deleted_at
        FROM visits WHERE user_id = ? ORDER BY started_at, id
      ) x
    SQL
  end

  def points_for(user)
    point_rows = rows(<<~SQL.squish, user.id)
      SELECT row_to_json(x)::text FROM (
        SELECT id, user_id, ST_AsText(lonlat) AS lonlat_wkt, "timestamp", accuracy, anomaly, visit_id,
               geodata::text AS geodata, reverse_geocoded_at::text AS reverse_geocoded_at, lock_version
        FROM points WHERE user_id = ? ORDER BY "timestamp", id
      ) x
    SQL
    point_rows.map { |row| row.merge('reverse_geocoded_at' => clock_state(row['reverse_geocoded_at'])) }
  end

  def point_claims(user)
    rows(<<~SQL.squish, user.id)
      SELECT json_build_array(p."timestamp", floor(extract(epoch FROM v.started_at))::bigint)::text
      FROM points p LEFT JOIN visits v ON v.id = p.visit_id WHERE p.user_id = ? ORDER BY p."timestamp", p.id
    SQL
  end

  def notes_for(user)
    rows('SELECT row_to_json(x)::text FROM (SELECT id, user_id, attachable_type, attachable_id, body, ' \
         'floor(extract(epoch FROM noted_at))::bigint AS noted_at FROM notes WHERE user_id = ? ORDER BY id) x',
         user.id)
  end

  def place_visits_for(user)
    rows('SELECT row_to_json(x)::text FROM (SELECT pv.id, pv.place_id, pv.visit_id FROM place_visits pv ' \
         'JOIN visits v ON v.id = pv.visit_id WHERE v.user_id = ? ORDER BY pv.id) x', user.id)
  end

  def notifications_for(user)
    rows('SELECT row_to_json(x)::text FROM (SELECT kind, title, content FROM notifications ' \
         'WHERE user_id = ? ORDER BY id) x', user.id)
  end

  def visits_input(user)
    { 'users' => [user_row(user)], 'instance_settings' => instance_setting_rows, 'areas' => areas_for(user),
      'places' => places_for(user), 'tags' => tags_for(user), 'taggings' => taggings_for(user),
      'visits' => visits_for(user), 'place_visits' => place_visits_for(user), 'notes' => notes_for(user),
      'points' => points_for(user) }.reject { |_table, table_rows| table_rows.empty? }
  end

  def policy_dump(user)
    policy = Visits::Detection::Policy.for(user)
    { 'stay_radius_m' => policy.stay_radius_m, 'min_dwell_s' => policy.min_dwell_s,
      'min_points' => policy.min_points, 'merge_gap_s' => policy.merge_gap_s,
      'suggestions_enabled' => user.safe_settings.visits_suggestions_enabled? }
  end

  def detection_result(user, returned, first_request)
    { 'returned' => returned.size, 'visits' => visits_for(user), 'point_claims' => point_claims(user),
      'places' => places_for(user), 'tags' => tags_for(user), 'effects' => visit_effects,
      'requests' => http[first_request..] }
  end

  def run_detection(user, from, to, via)
    months.clear
    clear_enqueued_jobs
    first_request = http.size
    returned = if via == :suggest
                 Visits::Suggest.new(user, start_at: from, end_at: to).call
               else
                 Visits::SmartDetect.new(user, start_at: from, end_at: to).call
               end
    detection_result(user.reload, returned, first_request)
  end

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

  def write_stage_fixture(dir, name, data)
    path = Rails.root.join("app-phoenix/test/fixtures/#{dir}/#{name}.json")
    FileUtils.mkdir_p(path.dirname)
    File.write(path, "#{exact_json(data.merge('postgis_build' => postgis_build))}\n")
  end

  def detection_fixture(name, user, from, to, runs: 1, via: :detect)
    input = visits_input(user)
    policy = policy_dump(user)
    first = run_detection(user, from, to, via)
    stage_dumps = plain(stages)
    rerun = runs > 1 ? { 'rerun' => run_detection(user, from, to, via) } : {}
    fixture = {
      'input' => input, 'policy' => policy,
      'run' => { 'via' => via.to_s, 'start_at' => from, 'end_at' => to, 'time_zone' => Time.zone.tzinfo.name },
      'stages' => stage_dumps, 'expected' => first
    }
    write_stage_fixture('visits', name, fixture.merge(rerun))
  end

  def dwell(user, lat_offset, start_ts, count: 6, step: 600, geodata: {})
    Array.new(count) do |i|
      jitter = i * 0.00001
      create(:point, user:, lonlat: leipzig(lat_offset + jitter, jitter), timestamp: start_ts + (i * step),
                     accuracy: 10, geodata:)
    end
  end

  def poi_geodata(name, key, value)
    { 'type' => 'Feature', 'properties' => { 'name' => name, 'osm_key' => key, 'osm_value' => value } }
  end

  def stub_near(lat, body)
    stub_request(:get, %r{https://photon\.selfhosted\.example\.test/reverse}).with do |request|
      (request.uri.query_values['lat'].to_f - lat).abs < 0.001
    end.to_return(json_response(body))
  end

  def photon_collection(lat, lon, properties)
    { type: 'FeatureCollection',
      features: [{ type: 'Feature', properties:, geometry: { type: 'Point', coordinates: [lon, lat] } }] }
  end

  def machine_visit(user, started_at, ended_at, place: nil)
    create(:visit, user:, area: nil, place:, started_at: Time.zone.at(started_at), ended_at: Time.zone.at(ended_at),
                   duration: (ended_at - started_at) / 60, name: place&.name || 'Existing Visit', status: :suggested,
                   detection_version: Visits::Detection::VERSION)
  end

  it 'attributes stays to an area, a known place, a POI vote, a venue, an address, or nothing' do
    user = create(:user, email: 'w5b-visits-attribution@example.test')
    configure_instance_geocoding(photon_api_host: 'photon.selfhosted.example.test', photon_api_use_https: true)
    use_real_geocoding_lookups
    allow(Geocoding::RateLimiter).to receive(:sleep)
    create(:area, user:, name: 'Home', latitude: leipzig_lat, longitude: leipzig_lon, radius: 100)
    create(:place, user:, name: 'My Cafe', latitude: leipzig_lat(0.0053), longitude: leipzig_lon, source: :manual)
    bistro = create(:place, user:, name: 'Photon Bistro', latitude: leipzig_lat(0.005), longitude: leipzig_lon,
                            source: :photon)
    2.times do |i|
      create(:visit, user:, area: nil, place: bistro, status: :confirmed, name: 'Photon Bistro',
                     started_at: Time.zone.at(base_ts - 40.days + (i * 1.day)),
                     ended_at: Time.zone.at(base_ts - 40.days + (i * 1.day) + 1.hour), duration: 60)
    end
    hour = 3600
    dwell(user, 0.0, base_ts)
    dwell(user, 0.005, base_ts + (3 * hour))
    dwell(user, 0.010, base_ts + (6 * hour), geodata: poi_geodata('Fixture Bakery', 'shop', 'bakery'))
    dwell(user, 0.015, base_ts + (9 * hour))
    dwell(user, 0.020, base_ts + (12 * hour))
    dwell(user, 0.025, base_ts + (15 * hour))
    stub_near(leipzig_lat(0.015), photon_collection(leipzig_lat(0.015), leipzig_lon,
                                                    { name: 'Fixture Venue', osm_key: 'amenity', osm_value: 'cafe' }))
    stub_near(leipzig_lat(0.020), photon_collection(leipzig_lat(0.020), leipzig_lon,
                                                    { street: 'Fixturestrasse', housenumber: '12',
                                                      osm_key: 'building', osm_value: 'yes' }))
    stub_near(leipzig_lat(0.025), { type: 'FeatureCollection', features: [] })
    detection_fixture('attribution_detection', user, base_ts - hour, base_ts + (18 * hour))
  end

  it 'mints a place whose float centre falls in the BigDecimal/cast divergence window' do
    user = create(:user, email: 'w5b-visits-decimal-cast@example.test')
    offsets = [0.0397124999, 0.0397124999, 0.0397124999, 0.0397125002]
    offsets.each_with_index do |offset, i|
      create(:point, user:, lonlat: "POINT(#{12.3 + offset} #{51.3 + offset})", timestamp: base_ts + (i * 600),
                     accuracy: 10, geodata: poi_geodata('Fixture Coffeehouse', 'amenity', 'cafe'))
    end
    detection_fixture('decimal_cast_attribution', user, base_ts - 3600, base_ts + 7200)
    center = stages['attributed'].flatten.first['center_lat']
    column_type = Place.type_for_attribute('latitude')
    expect(BigDecimal(center, 10).round(6)).not_to eq(column_type.cast(center))
  end

  it 'runs the detection pipeline stage by stage over a colocated dwell' do
    user = create(:user, email: 'w5b-visits-pipeline@example.test')
    (0..5).each do |i|
      create(:point, user:, timestamp: base_ts + (i * 600), lonlat: leipzig(i * 0.00002, i * 0.00002), accuracy: 10)
    end
    detection_fixture('detection_pipeline', user, base_ts - 3600, base_ts + 7200)
  end

  it 'trims a stay around a confirmed and a tombstoned anchor' do
    user = create(:user, email: 'w5b-visits-anchors@example.test')
    dwell(user, 0.0, base_ts, count: 12)
    create(:visit, user:, area: nil, place: nil, status: :confirmed, name: 'Confirmed Anchor',
                   started_at: Time.zone.at(base_ts + 1800), ended_at: Time.zone.at(base_ts + 3000), duration: 20)
    create(:visit, user:, area: nil, place: nil, status: :suggested, name: 'Tombstone', deleted_at: Time.current,
                   started_at: Time.zone.at(base_ts + 4800), ended_at: Time.zone.at(base_ts + 5400), duration: 10)
    detection_fixture('anchors_trim', user, base_ts - 3600, base_ts + 10_800)
  end

  it 'writes nothing when an unchanged window is detected again' do
    user = create(:user, email: 'w5b-visits-rerun@example.test')
    create(:area, user:, name: 'Office', latitude: leipzig_lat, longitude: leipzig_lon, radius: 100)
    dwell(user, 0.0, base_ts)
    detection_fixture('unchanged_rerun', user, base_ts - 3600, base_ts + 7200, runs: 2)
  end

  def fresh_and_covered(user)
    covered = create(:place, user:, name: 'Covered Place', latitude: leipzig_lat, longitude: leipzig_lon,
                             source: :manual)
    create(:place, user:, name: 'Fresh Place', latitude: leipzig_lat(0.005), longitude: leipzig_lon, source: :manual)
    dwell(user, 0.0, base_ts)
    dwell(user, 0.005, base_ts + 10_800)
    machine_visit(user, base_ts + 600, base_ts + 2400, place: covered)
  end

  it 'requests place geocoding once per place of a fresh visit, never for a covered one' do
    user = create(:user, email: 'w5b-visits-suggest-fresh@example.test')
    configure_instance_geocoding(photon_api_host: 'photon.selfhosted.example.test', photon_api_use_https: true)
    fresh_and_covered(user)
    detection_fixture('suggest_fresh_vs_covered', user, base_ts - 3600, base_ts + 18_000, via: :suggest)
  end

  it 'requests no place geocoding when geocoding is disabled' do
    user = create(:user, email: 'w5b-visits-suggest-disabled@example.test')
    fresh_and_covered(user)
    detection_fixture('suggest_geocoding_disabled', user, base_ts - 3600, base_ts + 18_000, via: :suggest)
  end

  it 'adopts a demo place and its demo tag when a visit claims it' do
    user = create(:user, email: 'w5b-visits-demo@example.test')
    place = create(:place, user:, name: 'Demo Cafe', latitude: leipzig_lat, longitude: leipzig_lon, source: :manual,
                           demo: true)
    tag = create(:tag, user:, name: 'Demo Tag', color: '#123456', icon: '📍', demo: true)
    Tagging.create!(tag:, taggable: place)
    dwell(user, 0.0, base_ts)
    detection_fixture('demo_adoption', user, base_ts - 3600, base_ts + 7200)
  end

  it 'treats a suggested visit with a note as an anchor' do
    user = create(:user, email: 'w5b-visits-noted@example.test')
    dwell(user, 0.0, base_ts, count: 12)
    noted = machine_visit(user, base_ts + 1800, base_ts + 3000)
    Note.create!(user:, attachable: noted, body: 'Fixture note', noted_at: Time.zone.at(base_ts + 2400))
    detection_fixture('machine_visit_with_note', user, base_ts - 3600, base_ts + 10_800)
  end

  it 'finds no machine visit at all while a note with a NULL attachable_id exists' do
    user = create(:user, email: 'w5b-visits-null-note@example.test')
    dwell(user, 0.0, base_ts, count: 12)
    machine_visit(user, base_ts + 1800, base_ts + 3000)
    Note.connection.exec_insert(
      Note.sanitize_sql_array([
                                'INSERT INTO notes (user_id, attachable_type, attachable_id, body, noted_at, ' \
                                'created_at, updated_at) VALUES (?, ?, NULL, ?, ?, now(), now())',
                                user.id, 'Visit', 'Orphaned note', Time.zone.at(base_ts)
                              ])
    )
    detection_fixture('null_attachable_note', user, base_ts - 3600, base_ts + 10_800)
  end

  it 'stitches a stay that straddles the monthly batch edge of a 40-day window' do
    user = create(:user, email: 'w5b-visits-stitch@example.test')
    edge = Time.zone.local(2026, 10, 1).to_i
    dwell(user, 0.0, edge - 1800, count: 8)
    detection_fixture('batch_edge_stitch', user, Time.zone.local(2026, 9, 1).to_i, Time.zone.local(2026, 10, 10).to_i)
  end

  def suggest_calls
    calls = []
    allow(Visits::Suggest).to receive(:new).and_wrap_original do |original, user, start_at:, end_at:|
      calls << [start_at.to_i, end_at.to_i]
      original.call(user, start_at:, end_at:)
    end
    calls
  end

  it 'chunks a DST-crossing calendar range and a DateTime range, and splits months, as Rails does' do
    user = create(:user, email: 'w5b-visits-calendar@example.test', settings: { 'timezone' => 'Europe/Berlin' })
    calls = suggest_calls
    ranges = [%w[2026-03-28T02:30:00 2026-03-31T00:00:00], %w[2026-03-28T12:00:00 2026-03-31T00:00:00]]
    calendar = ranges.map do |from, to|
      calls.clear
      VisitSuggestingJob.perform_now(user_id: user.id, start_at: from, end_at: to)
      { 'start_at' => from, 'end_at' => to, 'chunks' => calls.dup }
    end
    calls.clear
    fixed_start = DateTime.new(2026, 3, 28, 1, 30)
    fixed_end = DateTime.new(2026, 3, 30, 22, 0)
    VisitSuggestingJob.perform_now(user_id: user.id, start_at: fixed_start, end_at: fixed_end)
    fixed = calls.dup
    batch_start = Time.use_zone('Europe/Berlin') { Time.zone.local(2026, 2, 10, 12).to_i }
    batch_end = Time.use_zone('Europe/Berlin') { Time.zone.local(2026, 5, 5, 12).to_i }
    month_batches = Time.use_zone('Europe/Berlin') do
      Visits::Detection::Runner.new(user, start_at: batch_start, end_at: batch_end).send(:batch_ranges)
    end
    redetect_months = Visits::Detection::HistoryRedetect.new(user).send(:monthly_ranges, batch_start, batch_end)
    fixture = {
      'input' => { 'users' => [user_row(user)] },
      'calendar' => { 'time_zone' => 'Europe/Berlin', 'ranges' => calendar },
      'fixed' => { 'start_at' => fixed_start.to_i, 'end_at' => fixed_end.to_i, 'chunks' => fixed },
      'month_batches' => { 'time_zone' => 'Europe/Berlin', 'start_at' => batch_start, 'end_at' => batch_end,
                           'batches' => month_batches },
      'redetect_months' => { 'time_zone' => Time.zone.tzinfo.name, 'min_ts' => batch_start, 'max_ts' => batch_end,
                             'months' => redetect_months }
    }
    write_fixture('visits', 'calendar_dst', fixture)
  end

  it 'resolves the detection policy from defaults, clamps and string settings' do
    cases = {
      'defaults' => {},
      'radius_string_clamped' => { 'visit_radius_meters' => '2' },
      'min_duration_nil' => { 'visit_min_duration_minutes' => nil },
      'suggestions_boolean_true' => { 'visits_suggestions_enabled' => true },
      'min_points_clamped' => { 'visit_min_points' => '50', 'merge_threshold_minutes' => '7' },
      'suggestions_string_false' => { 'visits_suggestions_enabled' => 'false', 'visit_radius_meters' => 900 }
    }.map do |name, settings|
      user = create(:user, email: "w5b-visits-settings-#{name.tr('_', '-')}@example.test", settings:)
      { 'name' => name, 'settings' => user.reload.settings, 'expected' => policy_dump(user) }
    end
    write_fixture('visits', 'settings_policy', { 'cases' => cases })
  end

  it 'rescores a legacy visit from its own points' do
    user = create(:user, email: 'w5b-visits-legacy-confidence@example.test')
    policy = Visits::Detection::Policy.for(user)
    area = create(:area, user:, name: 'Fixture Area', latitude: leipzig_lat, longitude: leipzig_lon, radius: 80)
    visit = create(:visit, user:, area:, started_at: Time.zone.at(base_ts), ended_at: Time.zone.at(base_ts + 3600),
                           duration: 60, status: :confirmed, confidence: nil, confidence_breakdown: {})
    (0..4).each do |i|
      create(:point, user:, timestamp: base_ts + (i * 500), lonlat: leipzig(i * 0.00001, i * 0.00001), accuracy: 8,
                     visit_id: visit.id)
    end
    input = visits_input(user)
    Visits::Detection::VisitRescore.call(visit, policy)
    fixture = { 'input' => input, 'expected' => { 'visits' => visits_for(user) } }
    write_fixture('visits', 'legacy_confidence_backfill', fixture)
  end

  def redetect_user(email, locale)
    user = create(:user, email:, settings: { 'locale' => locale })
    user.update_columns(visits_redetected_at: nil)
    [6, 7, 8].each_with_index do |month, i|
      dwell(user, i * 0.005, Time.utc(2026, month, 15, 12).to_i)
    end
    user
  end

  def redetect_fixture(name, user, failing_month: nil)
    input = visits_input(user)
    min_ts, max_ts = user.points.pick(Arel.sql('min(timestamp)'), Arel.sql('max(timestamp)'))
    ranges = Visits::Detection::HistoryRedetect.new(user).send(:monthly_ranges, min_ts, max_ts)
    if failing_month
      failing_start = ranges[failing_month].first
      allow_any_instance_of(Visits::SmartDetect).to receive(:call).and_wrap_original do |original, *args|
        raise StandardError, 'Fixture month failure' if original.receiver.start_at == failing_start

        original.call(*args)
      end
    end
    months.clear
    clear_enqueued_jobs
    Visits::FullHistoryRedetectJob.perform_now(user.id)
    fixture = {
      'input' => input, 'months' => ranges, 'failing_month' => failing_month, 'time_zone' => Time.zone.tzinfo.name,
      'expected' => { 'user' => user_row(user.reload), 'notifications' => notifications_for(user),
                      'visits' => visits_for(user), 'point_claims' => point_claims(user), 'effects' => visit_effects }
    }
    write_fixture('visits', name, fixture)
  end

  it 're-detects three months into a complete notification in English' do
    redetect_fixture('full_history_redetect', redetect_user('w5b-visits-redetect-en@example.test', 'en'))
  end

  it 're-detects three months into a complete notification in Polish' do
    redetect_fixture('full_history_redetect_pl', redetect_user('w5b-visits-redetect-pl@example.test', 'pl'))
  end

  it 'reports a partial re-detection and keeps the cooldown unset when one month raises' do
    redetect_fixture('full_history_redetect_partial', redetect_user('w5b-visits-redetect-partial@example.test', 'en'),
                     failing_month: 1)
  end

  it 'notifies a suggestion failure once per hour' do
    user = create(:user, email: 'w5b-visits-suggest-error@example.test')
    dwell(user, 0.0, base_ts)
    key = "visit_suggest_error:user:#{user.id}"
    Sidekiq.redis { |redis| redis.call('DEL', key) }
    input = visits_input(user)
    allow_any_instance_of(Visits::SmartDetect).to receive(:call).and_raise(StandardError, 'Fixture failure')
    2.times { Visits::Suggest.new(user, start_at: base_ts - 3600, end_at: base_ts + 7200).call }
    ttl = Sidekiq.redis { |redis| redis.call('TTL', key) }
    fixture = {
      'input' => input,
      'run' => { 'start_at' => base_ts - 3600, 'end_at' => base_ts + 7200, 'calls' => 2,
                 'message' => 'Fixture failure' },
      'expected' => { 'notifications' => notifications_for(user),
                      'dedupe_key_ttl_within_hour' => ttl.between?(1, 3600) }
    }
    write_fixture('visits', 'suggest_error_notification', fixture)
  end
end
