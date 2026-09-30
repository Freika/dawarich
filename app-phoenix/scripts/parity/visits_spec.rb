# frozen_string_literal: true

require 'rails_helper'

LEIPZIG_LAT = 51.3397
LEIPZIG_LON = 12.3731

RSpec.describe 'Phoenix fixture: Rails visit detection' do
  include ActiveJob::TestHelper

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

  def clock_state(value)
    value.present? ? 'set' : nil
  end

  def user_row(user)
    rows('SELECT row_to_json(x)::text FROM (SELECT id, email, settings FROM users WHERE id = ?) x', user.id).first
  end

  def area_row(area)
    rows('SELECT row_to_json(x)::text FROM (SELECT id, user_id, name, latitude, longitude, radius FROM areas ' \
         'WHERE id = ?) x', area.id).first
  end

  def point_row(point)
    rows(<<~SQL.squish, point.id).first
      SELECT row_to_json(x)::text FROM (
        SELECT id, user_id, ST_AsText(lonlat) AS lonlat_wkt, "timestamp", accuracy, visit_id,
               geodata::text AS geodata
        FROM points WHERE id = ?
      ) x
    SQL
  end

  def place_row(place)
    rows(<<~SQL.squish, place.id).first
      SELECT row_to_json(x)::text FROM (
        SELECT id, user_id, name, ST_AsText(lonlat) AS lonlat_wkt, source
        FROM places WHERE id = ?
      ) x
    SQL
  end

  def visit_row(visit)
    row = rows(<<~SQL.squish, visit.id).first
      SELECT row_to_json(x)::text FROM (
        SELECT id, user_id, area_id, place_id, started_at::text AS started_at, ended_at::text AS ended_at,
               duration, name, status, confidence, confidence_breakdown::text AS confidence_breakdown
        FROM visits WHERE id = ?
      ) x
    SQL
    row.merge('started_at' => clock_state(row['started_at']), 'ended_at' => clock_state(row['ended_at']))
  end

  def write_fixture(name, data)
    path = Rails.root.join("app-phoenix/test/fixtures/visits/#{name}.json")
    FileUtils.mkdir_p(path.dirname)
    File.write(path, "#{JSON.pretty_generate(data.merge('postgis_build' => postgis_build))}\n")
  end

  def stay_for(points, extra = {})
    { point_ids: points.map(&:id), center_lat: points.sum(&:lat) / points.size.to_f,
      center_lon: points.sum(&:lon) / points.size.to_f, radius: 20 }.merge(extra)
  end

  it 'attributes a stay to an area, a known place, a POI vote, an address, or nothing' do
    user = create(:user, email: 'w5b-visits-attribution@example.test')
    policy = Visits::Detection::Policy.for(user)

    area = create(:area, user: user, name: 'Home', latitude: LEIPZIG_LAT, longitude: LEIPZIG_LON, radius: 100)
    area_points = create_list(:point, 3, user: user, lonlat: "POINT(#{LEIPZIG_LON} #{LEIPZIG_LAT})")
    area_stay = stay_for(area_points)
    area_result = Visits::Detection::PlaceAttributor.new(user, policy).call(area_stay)

    known_place = create(:place, user: user, name: 'My Cafe', latitude: 52.0, longitude: 13.0, source: :manual)
    known_points = create_list(:point, 3, user: user, lonlat: 'POINT(13.0 52.0)')
    known_stay = stay_for(known_points)
    known_result = Visits::Detection::PlaceAttributor.new(user, policy).call(known_stay)

    poi_geodata = { 'type' => 'Feature',
                     'properties' => { 'name' => 'Fixture Bakery', 'osm_key' => 'shop', 'osm_value' => 'bakery' } }
    poi_points = create_list(:point, 3, user: user, lonlat: 'POINT(14.0 53.0)', geodata: poi_geodata)
    poi_stay = stay_for(poi_points)
    poi_result = perform_enqueued_jobs do
      Visits::Detection::PlaceAttributor.new(user, policy).call(poi_stay)
    end || Visits::Detection::PlaceAttributor.new(user, policy).call(poi_stay)

    address_points = create_list(:point, 3, user: user, lonlat: 'POINT(15.0 54.0)')
    address_stay = stay_for(address_points)
    address_body = { type: 'FeatureCollection',
                      features: [{ type: 'Feature',
                                   properties: { street: 'Fixture Street', housenumber: '12', country: 'Germany',
                                                 osm_key: 'building', osm_value: 'yes' },
                                   geometry: { type: 'Point', coordinates: [15.0, 54.0] } }] }.to_json
    configure_instance_geocoding(photon_api_host: 'photon.selfhosted.example.test', photon_api_use_https: true)
    use_real_geocoding_lookups
    allow(Geocoding::RateLimiter).to receive(:sleep)
    stub_request(:get, %r{https://photon\.selfhosted\.example\.test/reverse})
      .with(query: hash_including('lat' => '54.0'))
      .to_return(status: 200, body: address_body, headers: { 'Content-Type' => 'application/json' })
    address_result = Visits::Detection::PlaceAttributor.new(user, policy).call(address_stay)

    none_points = create_list(:point, 3, user: user, lonlat: 'POINT(16.0 55.0)')
    none_stay = stay_for(none_points)
    empty_body = { type: 'FeatureCollection', features: [] }.to_json
    stub_request(:get, %r{https://photon\.selfhosted\.example\.test/reverse})
      .with(query: hash_including('lat' => '55.0'))
      .to_return(status: 200, body: empty_body, headers: { 'Content-Type' => 'application/json' })
    none_result = Visits::Detection::PlaceAttributor.new(user, policy).call(none_stay)

    fixture = {
      'input' => {
        'users' => [user_row(user)],
        'areas' => [area_row(area)],
        'places' => [place_row(known_place)],
        'points' => (area_points + known_points + poi_points + address_points + none_points).map { |p| point_row(p) }
      },
      'requests' => WebMock::RequestRegistry.instance.requested_signatures.hash.keys
                                            .select { |sig| sig.uri.to_s.include?('photon.selfhosted') }
                                            .map { |sig| { 'method' => sig.method.to_s, 'url' => sig.uri.to_s } },
      'expected' => {
        'area' => { 'evidence' => area_result[:evidence].to_s, 'name' => area_result[:name],
                    'area_id' => area_result[:area]&.id },
        'known_place' => { 'evidence' => known_result[:evidence].to_s, 'name' => known_result[:name],
                            'place_id' => known_result[:place]&.id },
        'poi' => { 'evidence' => poi_result[:evidence].to_s, 'name' => poi_result[:name],
                   'place' => poi_result[:place] ? place_row(poi_result[:place]) : nil },
        'address' => { 'evidence' => address_result[:evidence].to_s, 'name' => address_result[:name] },
        'none' => { 'evidence' => none_result[:evidence].to_s, 'name' => none_result[:name] }
      }
    }
    write_fixture('place_attribution', fixture)
  end

  it 'mints a place whose float centre falls in the BigDecimal/cast divergence window' do
    user = create(:user, email: 'w5b-visits-decimal-cast@example.test')
    policy = Visits::Detection::Policy.for(user)
    offsets = [0.0397124999, 0.0397124999, 0.0397124999, 0.0397125002]
    points = offsets.each_with_index.map do |offset, i|
      create(:point, user: user, lonlat: "POINT(#{12.3 + offset} #{51.3 + offset})",
                     timestamp: 1_790_000_000 + (i * 60))
    end
    stay = stay_for(points)
    column_type = Place.type_for_attribute('latitude')
    expect(BigDecimal(stay[:center_lat], 10).round(6)).not_to eq(column_type.cast(stay[:center_lat]))

    geodata = { 'type' => 'Feature',
                'properties' => { 'name' => 'Fixture Coffeehouse', 'osm_key' => 'amenity', 'osm_value' => 'cafe' } }
    points.each { |p| p.update_columns(geodata: geodata) }
    result = Visits::Detection::PlaceAttributor.new(user, policy).call(stay)

    fixture = {
      'input' => { 'users' => [user_row(user)], 'points' => points.map { |p| point_row(p) } },
      'stay_center' => { 'center_lat' => stay[:center_lat], 'center_lon' => stay[:center_lon] },
      'decimal_cast' => { 'bigdecimal_round6' => BigDecimal(stay[:center_lat], 10).round(6).to_s('F'),
                          'column_cast' => column_type.cast(stay[:center_lat]).to_s('F') },
      'expected' => { 'evidence' => result[:evidence].to_s, 'name' => result[:name],
                      'place' => result[:place] ? place_row(result[:place]) : nil }
    }
    write_fixture('decimal_cast_attribution', fixture)
  end

  it 'runs the detection pipeline stage by stage over a colocated dwell' do
    user = create(:user, email: 'w5b-visits-pipeline@example.test')
    policy = Visits::Detection::Policy.for(user)
    base = 1_790_000_000
    points = (0..5).map do |i|
      create(:point, user: user, timestamp: base + (i * 600),
                     lonlat: "POINT(#{LEIPZIG_LON + (i * 0.00002)} #{LEIPZIG_LAT + (i * 0.00002)})", accuracy: 10)
    end
    points_by_id = points.index_by(&:id)

    fragments = Visits::Detection::DwellSweep.new(policy).call(points)
    bridged = Visits::Detection::GapBridger.new(policy).call(fragments)
    reconciled = Visits::Detection::MovementReconciler.new(policy).call(bridged, [])
    stays = Visits::Detection::StayAssembler.new(policy).call(reconciled, points_by_id)
    attributed = stays.map do |stay|
      attributor_result = Visits::Detection::PlaceAttributor.new(user, policy).call(stay)
      stay.merge(attributor_result).merge(
        Visits::Detection::StayScoring.attributes(stay.merge(attributor_result), points_by_id, policy)
      )
    end

    dumper = lambda do |stage|
      stage.map { |f| f.each_with_object({}) { |(k, v), h| h[k.to_s] = v.is_a?(Symbol) ? v.to_s : v } }
    end

    fixture = {
      'input' => { 'users' => [user_row(user)], 'points' => points.map { |p| point_row(p) } },
      'policy' => { 'stay_radius_m' => policy.stay_radius_m, 'min_dwell_s' => policy.min_dwell_s,
                    'min_points' => policy.min_points, 'merge_gap_s' => policy.merge_gap_s },
      'expected' => {
        'fragments' => dumper.call(fragments).map { |f| f.except('first', 'last', 'drift_ref') },
        'bridged' => dumper.call(bridged),
        'reconciled' => dumper.call(reconciled),
        'stays' => dumper.call(stays),
        'attributed' => attributed.map do |a|
          a.except(:area, :place).transform_values { |v| v.is_a?(Symbol) ? v.to_s : v }
           .transform_keys(&:to_s)
        end
      }
    }
    write_fixture('detection_pipeline', fixture)
  end

  it 'chunks a DST-crossing range and a DateTime range the same way Rails does' do
    Time.use_zone('Europe/Berlin') do
      start_at = Time.zone.local(2026, 3, 28, 2, 30)
      end_at = Time.zone.local(2026, 3, 31, 0, 0)
      chunks = Visits::TimeChunks.new(start_at: start_at, end_at: end_at).call

      datetime_start = DateTime.new(2026, 3, 28, 2, 30)
      datetime_end = DateTime.new(2026, 3, 31, 0, 0)
      datetime_chunks = Visits::TimeChunks.new(start_at: datetime_start, end_at: datetime_end).call

      fixture = {
        'input' => { 'start_at' => start_at.iso8601, 'end_at' => end_at.iso8601, 'zone' => 'Europe/Berlin' },
        'expected' => {
          'time_chunks' => chunks.map { |c| [c.begin.iso8601, c.end.iso8601, c.exclude_end?] },
          'datetime_chunks' => datetime_chunks.map { |c| [c.begin.to_s, c.end.to_s, c.exclude_end?] }
        }
      }
      write_fixture('calendar_dst', fixture)
    end
  end

  it 'rescues confidence for a legacy visit from its own points' do
    user = create(:user, email: 'w5b-visits-legacy-confidence@example.test')
    policy = Visits::Detection::Policy.for(user)
    area = create(:area, user: user, name: 'Fixture Area', latitude: LEIPZIG_LAT, longitude: LEIPZIG_LON, radius: 80)
    visit = create(:visit, user: user, area: area, started_at: Time.zone.at(1_790_000_000),
                            ended_at: Time.zone.at(1_790_003_600), status: :confirmed,
                            confidence: nil, confidence_breakdown: {})
    points = (0..4).map do |i|
      create(:point, user: user, timestamp: 1_790_000_000 + (i * 500),
                     lonlat: "POINT(#{LEIPZIG_LON + (i * 0.00001)} #{LEIPZIG_LAT + (i * 0.00001)})",
                     accuracy: 8, visit_id: visit.id)
    end
    visit_before = visit_row(visit)

    Visits::Detection::VisitRescore.call(visit, policy)
    visit.reload

    fixture = {
      'input' => { 'users' => [user_row(user)], 'areas' => [area_row(area)], 'visits' => [visit_before],
                   'points' => points.map { |p| point_row(p) } },
      'expected' => { 'visit' => visit_row(visit) }
    }
    write_fixture('legacy_confidence_backfill', fixture)
  end
end
