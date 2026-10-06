# frozen_string_literal: true

require 'rails_helper'
require_relative 'fixture_recording'

module ApiMapGoldenOracle
  TABLES = %w[users countries point_sources tracks track_segments points].freeze
  OWNER = 810_001
  OTHER = 810_002
  KEY = 'phoenix-a4map-golden-key'
  STAMP = '2026-09-01 12:00:00'
  T0 = 1_735_689_600
  P = '/api/v1/points'
  T = '/api/v1/tracks'
  E = 'end_at=1790856000'
  LAT = 'min_latitude=51&max_latitude=53'
  BBOX = "min_longitude=12&max_longitude=14&#{LAT}".freeze
  ACCEPT = { json: { 'Accept' => 'application/json' }, any: { 'Accept' => '*/*' }, none: {},
             xml: { 'Accept' => 'application/xml' },
             browser: { 'Accept' => 'text/html,application/xhtml+xml,*/*;q=0.8' } }.freeze
  NOW_ETAG = %w[etag].freeze
  POSTGIS_FLOAT_FIELDS = %w[avg_speed].freeze
  POSTGIS_FLOAT_PRECISION = 8
  CASES = [
    { name: 'points_default', path: P, ignore: NOW_ETAG },
    { name: 'points_end', path: "#{P}?#{E}" },
    { name: 'points_slim', path: "#{P}?slim=true&#{E}" },
    { name: 'points_slim_one', path: "#{P}?slim=1&#{E}" },
    { name: 'points_asc', path: "#{P}?order=asc&#{E}" },
    { name: 'points_order_upper', path: "#{P}?order=DESC&#{E}" },
    { name: 'points_page', path: "#{P}?per_page=2&page=2&#{E}" },
    { name: 'points_page_zero', path: "#{P}?per_page=0&page=0&#{E}" },
    { name: 'points_page_negative', path: "#{P}?per_page=-2&page=-1&#{E}" },
    { name: 'points_page_coerce', path: "#{P}?per_page=2junk&page=2junk&#{E}" },
    { name: 'points_page_past_end', path: "#{P}?per_page=3&page=9&#{E}" },
    { name: 'points_cap', path: "#{P}?per_page=10001&#{E}" },
    { name: 'points_include_anomalies', path: "#{P}?include_anomalies=true&#{E}" },
    { name: 'points_only_anomalies', path: "#{P}?anomalies_only=true&include_anomalies=true&#{E}" },
    { name: 'points_false_anomalies', path: "#{P}?include_anomalies=off&anomalies_only=0&#{E}" },
    { name: 'points_truthy_anomalies', path: "#{P}?include_anomalies=arbitrary&#{E}" },
    { name: 'points_range', path: "#{P}?start_at=1735689601&end_at=1735690000" },
    { name: 'points_date_range', path: "#{P}?start_at=2025-01-01&end_at=2025-01-02" },
    { name: 'points_date_range_berlin', path: "#{P}?start_at=2025-01-01&end_at=2025-01-02",
      user: { timezone: 'Europe/Berlin' } },
    { name: 'points_map_client_format', path: "#{P}?start_at=2025-01-01T01:01%2B01:00&end_at=2025-01-01T01:05%2B01:00",
      user: { timezone: 'Europe/Berlin' } },
    { name: 'points_utc_iso_fraction', path: "#{P}?start_at=2025-01-01T00:00:59.5Z&end_at=2025-01-01T00:04:00Z" },
    { name: 'points_clamp', path: "#{P}?start_at=0&end_at=9999999999" },
    { name: 'points_empty_range', path: "#{P}?start_at=1735776000&end_at=1735689600" },
    { name: 'points_import', path: "#{P}?import_id=820001&#{E}" },
    { name: 'points_import_garbage', path: "#{P}?import_id=bad&#{E}" },
    { name: 'points_bbox', path: "#{P}?#{BBOX}&#{E}" },
    { name: 'points_bbox_tight', path: "#{P}?min_longitude=13.0005&max_longitude=13.0025&#{LAT}&#{E}" },
    { name: 'points_bbox_hex', path: "#{P}?min_longitude=0x1p2&max_longitude=14&#{LAT}&#{E}" },
    { name: 'points_partial_bbox', path: "#{P}?min_longitude=garbage&#{E}" },
    { name: 'points_bbox_invalid', path: "#{P}?min_longitude=garbage&max_longitude=14&#{LAT}" },
    { name: 'points_bbox_inverted', path: "#{P}?min_longitude=14&max_longitude=12&#{LAT}" },
    { name: 'points_bbox_out_of_range', path: "#{P}?min_longitude=-181&max_longitude=14&#{LAT}" },
    { name: 'points_bbox_infinite', path: "#{P}?min_longitude=1e999&max_longitude=14&#{LAT}" },
    { name: 'points_bbox_nan', path: "#{P}?min_longitude=NaN&max_longitude=14&#{LAT}" },
    { name: 'points_if_none_match', path: "#{P}?#{E}", conditional: :etag },
    { name: 'points_if_none_match_list', path: "#{P}?#{E}", conditional: :etag_list },
    { name: 'points_if_none_match_star', path: "#{P}?#{E}", headers: { 'If-None-Match' => '*' } },
    { name: 'points_if_modified_since', path: "#{P}?#{E}", conditional: :since },
    { name: 'points_if_modified_since_stale', path: "#{P}?#{E}",
      headers: { 'If-Modified-Since' => 'Tue, 31 Dec 2024 00:00:00 GMT' } },
    { name: 'points_strict_freshness', path: "#{P}?#{E}", conditional: :both },
    { name: 'points_if_none_match_slim', path: "#{P}?slim=true&#{E}", conditional: :etag },
    { name: 'points_zone_new_york', path: "#{P}?#{E}", user: { timezone: 'America/New_York' } },
    { name: 'points_zone_rails_name', path: "#{P}?#{E}", user: { timezone: 'Berlin' } },
    { name: 'points_jsonb_order', path: "#{P}?start_at=1735689600&end_at=1735689600", seed: :jsonb,
      user: { timezone: 'Europe/Berlin' } },
    { name: 'points_empty', path: "#{P}?#{E}", seed: :none },
    { name: 'points_query_key', path: "#{P}?#{E}", auth: :query },
    { name: 'points_no_accept', path: "#{P}?#{E}", accept: :none },
    { name: 'points_accept_any', path: "#{P}?#{E}", accept: :any },
    { name: 'points_accept_browser', path: "#{P}?#{E}", accept: :browser },
    { name: 'points_accept_language', path: "#{P}?#{E}", headers: { 'Accept-Language' => 'de' } },
    { name: 'points_accept_xml', path: "#{P}?#{E}", accept: :xml },
    { name: 'points_format_xml', path: "#{P}?format=xml&#{E}" },
    { name: 'tracks_index', path: T },
    { name: 'tracks_page', path: "#{T}?per_page=1&page=2" },
    { name: 'tracks_page_coerce', path: "#{T}?per_page=1junk&page=0" },
    { name: 'tracks_per_page_uncapped', path: "#{T}?per_page=100000" },
    { name: 'tracks_overlap', path: "#{T}?start_at=2025-01-01T00:01:00Z&end_at=2025-01-01T00:04:00Z" },
    { name: 'tracks_overlap_fraction', path: "#{T}?start_at=2025-01-01T00:05:00.5Z&end_at=2025-01-01T02:00:00Z" },
    { name: 'tracks_date_only_berlin', path: "#{T}?start_at=2025-01-01&end_at=2025-01-01",
      user: { timezone: 'Europe/Berlin' } },
    { name: 'tracks_partial_date', path: "#{T}?start_at=2025-01-02" },
    { name: 'tracks_zone_berlin', path: T, user: { timezone: 'Europe/Berlin' } },
    { name: 'tracks_empty', path: T, seed: :none },
    { name: 'track_show', path: "#{T}/830001" },
    { name: 'track_show_legacy', path: "#{T}/830002" },
    { name: 'track_show_leading_zero', path: "#{T}/0830001" },
    { name: 'track_show_zone_new_york', path: "#{T}/830001", user: { timezone: 'America/New_York' } },
    { name: 'track_show_missing', path: "#{T}/839999" },
    { name: 'track_show_foreign', path: "#{T}/830003" },
    { name: 'track_show_clip', path: "#{T}/830001?start_at=1735689660&end_at=1735689780" },
    { name: 'track_show_clip_iso', path: "#{T}/830001?start_at=2025-01-01T01:01:00%2B01:00&end_at=2025-01-01T00:03:00Z",
      user: { timezone: 'Europe/Berlin' } },
    { name: 'track_show_range_covers', path: "#{T}/830001?start_at=1735689000&end_at=1735690000" },
    { name: 'track_show_one_bound', path: "#{T}/830001?start_at=1735689660" },
    { name: 'track_show_import', path: "#{T}/830001?import_id=820001" },
    { name: 'track_show_import_and_clip', path: "#{T}/830001?import_id=820002&start_at=1735689600&end_at=1735689840" },
    { name: 'track_show_empty_import', path: "#{T}/830001?import_id=999999" },
    { name: 'track_show_bad_import', path: "#{T}/830001?import_id=bad" },
    { name: 'track_show_empty_import_any', path: "#{T}/830001?import_id=999999", accept: :any },
    { name: 'track_show_empty_import_no_accept', path: "#{T}/830001?import_id=999999", accept: :none },
    { name: 'track_show_if_none_match', path: "#{T}/830001", conditional: :etag },
    { name: 'track_points', path: "#{T}/830001/points" },
    { name: 'track_points_import', path: "#{T}/830001/points?import_id=820001" },
    { name: 'track_points_empty_import', path: "#{T}/830001/points?import_id=999999" },
    { name: 'track_points_page', path: "#{T}/830001/points?page=2&per_page=2" },
    { name: 'track_points_zero', path: "#{T}/830001/points?page=0&per_page=0" },
    { name: 'track_points_blank_per_page', path: "#{T}/830001/points?page=1&per_page=" },
    { name: 'track_points_per_page_clamp', path: "#{T}/830001/points?page=1&per_page=5000" },
    { name: 'track_show_empty_import_xml', path: "#{T}/830001?import_id=999999", accept: :xml },
    { name: 'track_show_degenerate_import', path: "#{T}/830001?import_id=820005", seed: :degenerate },
    { name: 'track_show_degenerate_window', path: "#{T}/830001?start_at=1735689630&end_at=1735689631",
      seed: :degenerate },
    { name: 'track_points_fallback', path: "#{T}/830002/points" },
    { name: 'track_points_fallback_import', path: "#{T}/830002/points?import_id=820003" },
    { name: 'track_points_missing', path: "#{T}/839999/points" },
    { name: 'track_points_foreign', path: "#{T}/830003/points" },
    { name: 'auth_none_points', path: "#{P}?#{E}", auth: :none },
    { name: 'auth_unknown_points', path: "#{P}?#{E}", auth: :unknown },
    { name: 'auth_pending_points', path: "#{P}?#{E}", user: { status: 3 } },
    { name: 'auth_inactive_points', path: "#{P}?#{E}", user: { status: 0 } },
    { name: 'auth_none_tracks', path: T, auth: :none },
    { name: 'auth_pending_tracks', path: T, user: { status: 3 } },
    { name: 'auth_expired_tracks', path: T, user: { active_until: '2001-01-01 00:00:00' } },
    { name: 'auth_unknown_track', path: "#{T}/830001", auth: :unknown },
    { name: 'auth_pending_track', path: "#{T}/830001", user: { status: 3 } },
    { name: 'auth_inactive_track_points', path: "#{T}/830001/points", user: { status: 0 } },
    { name: 'auth_expired_track_points', path: "#{T}/830001/points", user: { active_until: '2001-01-01 00:00:00' } },
    { name: 'replay_points_order_invalid', expect: :rails, path: "#{P}?order=random&#{E}" },
    { name: 'replay_points_loose_date', expect: :rails, path: "#{P}?start_at=Jan%201%202025&#{E}" },
    { name: 'replay_points_unparsable_date', expect: :rails, path: "#{P}?start_at=nonsense&#{E}" },
    { name: 'replay_points_negative_epoch', expect: :rails, path: "#{P}?start_at=-1&#{E}" },
    { name: 'replay_points_local_time_without_offset', expect: :rails,
      path: "#{P}?start_at=2025-01-01T00:00&#{E}" },
    { name: 'replay_points_null_geometry', expect: :rails, path: "#{P}?#{E}", seed: :null_geometry },
    { name: 'replay_points_loose_if_modified_since', expect: :rails, path: "#{P}?#{E}",
      headers: { 'If-Modified-Since' => 'yesterday' } },
    { name: 'replay_points_unknown_zone', expect: :rails, path: "#{P}?#{E}", user: { timezone: 'Mars/Olympus' } },
    { name: 'replay_tracks_unparsable_dates', expect: :rails, path: "#{T}?start_at=bad&end_at=bad" },
    { name: 'replay_tracks_epoch_dates', expect: :rails, path: "#{T}?start_at=1735689600&end_at=1735690000" },
    { name: 'replay_track_loose_clip', expect: :rails, path: "#{T}/830001?start_at=Jan%201%202025&end_at=1735689780" },
    { name: 'replay_track_client_header', expect: :rails, path: "#{T}/830001",
      headers: { 'X-Dawarich-Client' => 'ios' }, ignore: ['set-cookie'] },
    { name: 'rails_tracked_months', expect: :rails, path: "#{P}/tracked_months", auth: :none },
    { name: 'rails_points_json_suffix', expect: :rails, path: "#{P}.json?#{E}", auth: :none },
    { name: 'rails_points_head', expect: :rails, method: :head, path: "#{P}?#{E}", auth: :none },
    { name: 'rails_cloud_points', expect: :rails, path: "#{P}?#{E}", env: { 'SELF_HOSTED' => 'false' } },
    { name: 'rails_kill_switch_tracks', expect: :rails, path: T, env: { 'DAWARICH_RAILS_SLICES' => 'api_map_reads' } },
    { name: 'rails_track_id_shape', expect: :rails, path: "#{T}/abc", auth: :none },
    { name: 'rails_track_json_suffix', expect: :rails, path: "#{T}/830001.json", auth: :none },
    { name: 'rails_track_points_json_suffix', expect: :rails, path: "#{T}/830001/points.json", auth: :none },
    { name: 'rails_track_points_id_shape', expect: :rails, path: "#{T}/abc/points", auth: :none },
    { name: 'rails_point_tiles', expect: :rails, path: '/api/v1/tiles/points/1/1/1.mvt', auth: :none },
    { name: 'rails_point_update', expect: :rails, method: :patch, path: "#{P}/870001", auth: :none },
    { name: 'rails_points_bulk_destroy', expect: :rails, method: :delete, path: "#{P}/bulk_destroy", auth: :none }
  ].freeze

  def self.results
    @results ||= []
  end

  def self.setups
    @setups ||= {}
  end
end

RSpec.describe 'Phoenix fixture: golden map read API requests', type: :request do
  after(:all) do
    path = Rails.root.join('app-phoenix/test/fixtures/api_map/golden.json')
    fixture = { 'time_zone' => ENV.fetch('TIME_ZONE', nil), 'setups' => ApiMapGoldenOracle.setups.sort.to_h,
                'cases' => ApiMapGoldenOracle.results.sort_by { _1['name'] } }
    FixtureRecording.verify(path, "#{map_exact_json(fixture)}\n")
  end

  ApiMapGoldenOracle::CASES.each do |kase|
    it(kase[:name]) do
      defaults = { method: :get, auth: :bearer, accept: :json, expect: :own, env: {}, seed: :base, user: {} }
      ApiMapGoldenOracle.results << map_record(kase.reverse_merge(defaults))
    end
  end

  it 'isolates golden map seeds from orphaned point sources' do
    map_insert('point_sources', id: 850_999, digest: 'e' * 32,
                                created_at: ApiMapGoldenOracle::STAMP, updated_at: ApiMapGoldenOracle::STAMP)
    map_seed(seed: :none, user: {})

    expect(PointSource.exists?(850_999)).to be(false)
    closure = {}
    %w[points tracks].each do |layer|
      %w[base speed empty invalid partial].each do |variant|
        map_seed(seed: :base, user: {})
        %w[points tracks].each do |domain|
          [2025, 'all'].each do |year|
            Rails.cache.write("#{domain}:tile_epoch:#{ApiMapGoldenOracle::OWNER}:#{year}",
                              "synthetic-#{domain}-#{year}", raw: true)
          end
        end
        query = 'start_at=1735689600&end_at=1735690000'
        query += '&speed_coloring=true' if variant == 'speed'
        query += '&import_id=999999' if variant == 'empty'
        query = 'start_at=1735689600' if variant == 'partial'
        x = variant == 'invalid' ? 1024 : 548
        path = "/api/v1/tiles/#{layer}/10/#{x}/338.mvt?#{query}"
        get path, headers: { 'Authorization' => "Bearer #{ApiMapGoldenOracle::KEY}" }
        closure["#{layer}_#{variant}"] = {
          'setup' => map_closure_setup(ApiMapGoldenOracle::TABLES),
          'status' => response.status, 'body_base64' => Base64.strict_encode64(response.body),
          'headers' => response.headers.to_h.transform_keys(&:downcase)
                               .slice('content-type', 'cache-control', 'vary', 'etag')
        }
      end
    end
    map_seed(seed: :base, user: {})
    map_insert('visits', id: 790_001, user_id: ApiMapGoldenOracle::OWNER, name: 'synthetic', status: 1,
                         started_at: map_time(0), ended_at: map_time(300), duration: 5,
                         created_at: ApiMapGoldenOracle::STAMP, updated_at: ApiMapGoldenOracle::STAMP)
    cell = H3.from_geo_coordinates([52.0, 13.0], 8).to_s(16)
    stored_cells = [[cell, 2, ApiMapGoldenOracle::T0, ApiMapGoldenOracle::T0 + 300]]
    map_insert('stats', id: 780_001, user_id: ApiMapGoldenOracle::OWNER, year: 2025, month: 1,
                        distance: 987, h3_hex_ids: JSON.generate(stored_cells),
                        created_at: ApiMapGoldenOracle::STAMP, updated_at: ApiMapGoldenOracle::STAMP)
    {
      'timeline' => '/api/v1/timeline?start_at=2025-01-01T00:00:00Z&end_at=2025-01-01T23:59:59Z',
      'timeline_missing' => '/api/v1/timeline',
      'timeline_large' => '/api/v1/timeline?start_at=2025-01-01&end_at=2025-03-01',
      'visited' => '/api/v1/countries/visited?start_at=1735689600&end_at=1735690000',
      'visited_bad' => '/api/v1/countries/visited?start_at=bad&end_at=1735690000',
      'tracked_months' => '/api/v1/points/tracked_months',
      'hexagons' => '/api/v1/maps/hexagons?start_date=2025-01-01&end_date=2025-01-02',
      'bounds' => '/api/v1/maps/hexagons/bounds?start_date=2025-01-01&end_date=2025-01-02',
      'fog' => '/api/v1/maps/hexagons/fog?start_date=2025-01-01&end_date=2025-01-02',
      'fog_bad' => '/api/v1/maps/hexagons/fog?start_date=bad&end_date=2025-01-02'
    }.each do |name, path|
      get path, headers: { 'Authorization' => "Bearer #{ApiMapGoldenOracle::KEY}" }
      closure[name] = {
        'setup' => map_closure_setup(ApiMapGoldenOracle::TABLES + %w[visits stats]),
        'status' => response.status, 'body' => response.body
      }
    end
    get '/api/v1/countries/borders', headers: { 'Authorization' => "Bearer #{ApiMapGoldenOracle::KEY}" }
    closure['borders'] = { 'status' => response.status, 'sha256' => Digest::SHA256.hexdigest(response.body) }
    codes_path = Rails.root.join('app-phoenix/priv/country_codes.json')
    codes = JSON.parse(File.read(codes_path))
    stream = StringIO.new
    gzip = Zlib::GzipWriter.new(stream)
    gzip.mtime = 0
    gzip.write(response.body)
    gzip.close
    codes['borders_gzip_base64'] = Base64.strict_encode64(stream.string)
    codes['visited_aliases'] = Countries::NameAliases::ALIASES
    FixtureRecording.verify(codes_path, "#{Oj.dump(codes, mode: :strict, indent: 2)}\n")
    User.find(ApiMapGoldenOracle::OWNER).update_columns(settings: { 'timezone' => 'Europe/Berlin' })
    Rails.cache.delete("dawarich/user_#{ApiMapGoldenOracle::OWNER}_years_tracked")
    get '/api/v1/points/tracked_months', headers: { 'Authorization' => "Bearer #{ApiMapGoldenOracle::KEY}" }
    closure['tracked_months_berlin'] = { 'status' => response.status, 'body' => response.body }

    User.find(ApiMapGoldenOracle::OWNER).update_columns(settings: { 'timezone' => 'Etc/UTC' })
    map_insert('digests', id: 770_001, user_id: ApiMapGoldenOracle::OWNER, year: 2024, period_type: 1,
                         distance: 12_345, toponyms: '[]', created_at: ApiMapGoldenOracle::STAMP,
                         updated_at: ApiMapGoldenOracle::STAMP)
    %w[valid malformed].each do |variant|
      Users::Digest.find(770_001).update_columns(toponyms: { 'country' => 'Germany' }) if variant == 'malformed'
      setup = map_closure_setup(ApiMapGoldenOracle::TABLES + %w[visits stats digests])
      result = map_response({ method: :get, expect: :rails }, '/api/v1/digests/2024',
                            { 'Authorization' => "Bearer #{ApiMapGoldenOracle::KEY}" })
      closure["digest_#{variant}"] = result.merge('setup' => setup)
    end

    mcp_headers = { 'Authorization' => "Bearer #{ApiMapGoldenOracle::KEY}",
                    'Accept' => 'application/json', 'Content-Type' => 'application/json' }
    {
      'initialize' => { jsonrpc: '2.0', id: 1, method: 'initialize',
                        params: { protocolVersion: '2025-11-25', capabilities: {},
                                  clientInfo: { name: 'synthetic', version: '1' } } },
      'tools' => { jsonrpc: '2.0', id: 1, method: 'tools/list' },
      'latest' => { jsonrpc: '2.0', id: 1, method: 'tools/call',
                   params: { name: 'get_latest_location', arguments: {} } },
      'search' => { jsonrpc: '2.0', id: 1, method: 'tools/call',
                   params: { name: 'search_visits', arguments: { query: 'synthetic' } } },
      'timeline' => { jsonrpc: '2.0', id: 1, method: 'tools/call',
                   params: { name: 'get_timeline', arguments: { start_at: '2025-01-01', end_at: '2025-01-01' } } },
      'notification' => { jsonrpc: '2.0', method: 'notifications/initialized' },
      'batch' => []
    }.each do |name, payload|
      post '/api/v1/mcp', params: JSON.generate(payload), headers: mcp_headers
      closure["mcp_#{name}"] = { 'status' => response.status, 'body' => response.body }
    end
    get '/api/v1/mcp', headers: mcp_headers
    closure['mcp_get'] = { 'status' => response.status, 'body' => response.body }
    delete '/api/v1/mcp', headers: mcp_headers
    closure['mcp_delete'] = { 'status' => response.status, 'body' => response.body }

    FixtureRecording.verify(Rails.root.join('app-phoenix/test/fixtures/a12f2c/closure.json'),
                            "#{map_exact_json(closure)}\n", json_bodies: [%w[timeline body]])
  end

  def map_closure_setup(tables)
    tables.index_with do |table|
      ActiveRecord::Base.connection.select_values("SELECT row_to_json(t)::text FROM #{table} t ORDER BY id")
                        .map { JSON.parse(_1) }
    end
  end

  def map_exact_json(value, depth = 0)
    pad = '  ' * (depth + 1)
    case value
    when Hash
      return '{}' if value.empty?

      entries = value.map { |k, v| "#{pad}#{Oj.dump(k.to_s, mode: :strict)}: #{map_exact_json(v, depth + 1)}" }
      "{\n#{entries.join(",\n")}\n#{'  ' * depth}}"
    when Array
      return '[]' if value.empty?

      "[\n#{value.map { |v| "#{pad}#{map_exact_json(v, depth + 1)}" }.join(",\n")}\n#{'  ' * depth}]"
    when Float
      value.to_s
    else
      Oj.dump(value, mode: :strict)
    end
  end

  def map_record(kase)
    map_seed(kase)
    allow(DawarichSettings).to receive(:self_hosted?).and_return(false) if kase[:env]['SELF_HOSTED'] == 'false'
    headers = map_headers(kase)
    path = kase[:auth] == :query ? "#{kase[:path]}&api_key=#{ApiMapGoldenOracle::KEY}" : kase[:path]
    map_conditional(path, headers, kase[:conditional]) if kase[:conditional]
    setup = map_setup

    { 'name' => kase[:name], 'expect' => kase[:expect].to_s, 'ignore' => kase[:ignore] || [], 'env' => kase[:env],
      'setup' => setup,
      'request' => { 'method' => kase[:method].to_s.upcase, 'target' => path, 'headers' => headers.to_a },
      'response' => map_response(kase, path, headers) }
  end

  def map_response(kase, path, headers)
    send(kase[:method], path, headers: headers)
    headers = response.headers.to_h.transform_keys(&:downcase).except('date', 'content-length')
    headers['etag'] = 'W/"fixture-etag"'
    headers['set-cookie'] = 'fixture-session' if headers.key?('set-cookie')
    headers['x-request-id'] = 'fixture-request-id'
    headers['x-runtime'] = '0.000000'
    { 'status' => response.status, 'headers' => headers, 'body' => map_normalized_body(response.body) }
  rescue StandardError
    raise unless kase[:expect] == :rails

    { 'status' => 500, 'headers' => {}, 'body' => '' }
  end

  def map_setup
    rows = ApiMapGoldenOracle::TABLES.map do |table|
      values = ActiveRecord::Base.connection.select_values("SELECT row_to_json(t)::text FROM #{table} t ORDER BY id")
      [table, values.map { JSON.parse(_1) }]
    end
    key = Digest::SHA256.hexdigest(JSON.generate(rows))[0, 16]
    ApiMapGoldenOracle.setups[key] = rows
    key
  end

  def map_headers(kase)
    headers = { 'Host' => 'localhost' }.merge(ApiMapGoldenOracle::ACCEPT.fetch(kase[:accept]))
                                       .merge(kase[:headers] || {})
    headers['Authorization'] = "Bearer #{ApiMapGoldenOracle::KEY}" if kase[:auth] == :bearer
    headers['Authorization'] = 'Bearer phoenix-a4map-golden-unknown' if kase[:auth] == :unknown
    headers
  end

  def map_conditional(path, headers, kind)
    get path, headers: headers
    etag = response.headers['ETag']
    since = response.headers['Last-Modified']
    case kind
    when :etag then headers['If-None-Match'] = etag
    when :etag_list then headers['If-None-Match'] = "W/\"unrelated\", #{etag}"
    when :since then headers['If-Modified-Since'] = since
    when :both then headers.merge!('If-None-Match' => 'W/"unrelated"', 'If-Modified-Since' => since)
    end
  end

  def map_insert(table, row)
    connection = ActiveRecord::Base.connection
    columns = row.keys.map { connection.quote_column_name(_1) }.join(', ')
    values = row.values.map { connection.quote(_1.is_a?(Hash) ? JSON.generate(_1) : _1) }.join(', ')
    connection.execute("INSERT INTO #{table} (#{columns}) VALUES (#{values})")
  end

  def map_normalized_body(body)
    value = JSON.parse(body)
    Oj.dump(map_normalized_floats(value), mode: :strict, float_precision: 0)
  rescue JSON::ParserError
    body
  end

  def map_normalized_floats(value)
    case value
    when Array
      value.map { map_normalized_floats(_1) }
    when Hash
      value.to_h do |key, nested|
        nested = if ApiMapGoldenOracle::POSTGIS_FLOAT_FIELDS.include?(key) && nested.is_a?(Float)
                   nested.round(ApiMapGoldenOracle::POSTGIS_FLOAT_PRECISION)
                 else
                   nested
                 end
        [key, map_normalized_floats(nested)]
      end
    else
      value
    end
  end

  def map_time(offset) = Time.at(ApiMapGoldenOracle::T0 + offset).utc.strftime('%F %T.%6N')

  def map_seed(kase)
    oracle = ApiMapGoldenOracle
    FixtureCleanup.delete!(oracle::TABLES)
    user = { status: 1, timezone: 'UTC', active_until: nil }.merge(kase[:user])
    stamps = { created_at: oracle::STAMP, updated_at: oracle::STAMP }
    map_insert('users', id: oracle::OWNER, email: 'map-owner@example.invalid', api_key: oracle::KEY,
                        status: user[:status], active_until: user[:active_until],
                        settings: { 'timezone' => user[:timezone] }, visits_redetected_at: oracle::STAMP, **stamps)
    map_insert('users', id: oracle::OTHER, email: 'map-other@example.invalid', api_key: 'phoenix-a4map-golden-other',
                        status: 1, settings: { 'timezone' => 'UTC' }, visits_redetected_at: oracle::STAMP, **stamps)
    return if kase[:seed] == :none

    map_seed_base(stamps)
    send("map_seed_#{kase[:seed]}") unless kase[:seed] == :base
  end

  def map_seed_base(stamps)
    map_insert('countries', id: 840_001, name: 'Synthetic country', iso_a2: 'ZZ', iso_a3: 'ZZZ', **stamps)
    map_insert('point_sources', id: 850_001, digest: 'f' * 32, tracker_id: 'dimension-device', ssid: 'dim-ssid',
                                connection: 1, trigger: 5, battery_status: 2, inrids: '{r1}', **stamps)
    map_seed_tracks(stamps)
    map_seed_points(stamps)
  end

  def map_seed_tracks(stamps)
    line = 'SRID=4326;LINESTRING(13 52,13.002 52.002,13.004 52.004)'
    owner = ApiMapGoldenOracle::OWNER
    [[830_001, owner, 0, 987, 11.25, 5], [830_002, owner, 3600.6r, nil, nil, 4],
     [830_003, ApiMapGoldenOracle::OTHER, 0, 987, 11.25, 5]].each do |id, user_id, offset, distance, speed, mode|
      map_insert('tracks', id:, user_id:, start_at: map_time(offset), end_at: map_time(offset + 300),
                           original_path: line, distance:, avg_speed: speed, duration: 300, dominant_mode: mode,
                           lock_version: 2, **stamps)
    end
    path = 'SRID=4326;LINESTRING(13 52,13.002 52.002)'
    map_insert('track_segments', id: 860_001, track_id: 830_001, transportation_mode: 2, start_at: map_time(0),
                                 end_at: map_time(150), distance: 450, duration: 150, avg_speed: 10.8, confidence: 1,
                                 path:, **stamps)
    map_insert('track_segments', id: 860_002, track_id: 830_001, transportation_mode: 5, start_at: map_time(150),
                                 end_at: map_time(300), distance: 450, duration: 150, avg_speed: 10.8, confidence: 2,
                                 path:, **stamps)
    map_insert('track_segments', id: 860_003, track_id: 830_002, transportation_mode: 4, start_index: 0, end_index: 1,
                                 distance: 450, duration: 150, avg_speed: 10.8, confidence: 0, path:, **stamps)
    map_insert('track_segments', id: 860_004, track_id: 830_002, transportation_mode: 0, start_index: 2, end_index: 3,
                                 distance: 450, duration: nil, avg_speed: nil, confidence: 7, path: nil, **stamps)
  end

  def map_seed_points(stamps)
    owner = ApiMapGoldenOracle::OWNER
    8.times do |i|
      map_insert('points', id: 870_001 + i, user_id: i == 7 ? ApiMapGoldenOracle::OTHER : owner,
                           timestamp: ApiMapGoldenOracle::T0 + (i * 60),
                           lonlat: "SRID=4326;POINT(#{13 + (i * 0.001)} #{52 + (i * 0.001)})",
                           track_id: i < 6 ? 830_001 : nil, import_id: i < 3 ? 820_001 : 820_002, anomaly: i == 5,
                           tracker_id: 'legacy-device', topic: 'legacy-topic', source_id: i == 2 ? 850_001 : nil,
                           country_id: i == 1 ? 840_001 : nil, country_name: i.zero? ? 'Explicit country' : nil,
                           country: i == 3 ? 'Legacy country' : nil, altitude: 10,
                           altitude_decimal: i == 4 ? '10.00' : '10.25', course: '45.12345',
                           velocity: i == 6 ? nil : '12.5', battery: 80, battery_status: i == 6 ? 7 : 1,
                           connection: i == 6 ? 4 : 0, trigger: 1, mode: i == 4 ? 3 : nil,
                           in_regions: i == 1 ? '{home,work}' : '{}', motion_data: { 'activity' => 'synthetic' },
                           geodata: i == 4 ? { 'properties' => { 'name' => 'X', 'b' => 1.5 } } : {},
                           raw_data: { 'ignored' => 'synthetic' }, lock_version: i,
                           reverse_geocoded_at: i.zero? ? '2026-09-01 12:00:00.123456' : nil,
                           created_at: stamps[:created_at],
                           updated_at: i == 3 ? '2026-09-06 08:30:15.25' : stamps[:updated_at])
    end
    3.times do |i|
      map_insert('points', id: 870_101 + i, user_id: owner, timestamp: ApiMapGoldenOracle::T0 + 3600 + (i * 60),
                           lonlat: "SRID=4326;POINT(14 #{53 + (i * 0.001)})", import_id: 820_003 + (i % 2), **stamps)
    end
    map_insert('points', id: 870_201, user_id: owner, timestamp: Time.utc(2024, 12, 31, 23, 59).to_i,
                         lonlat: 'SRID=4326;POINT(12 51)', anomaly: true, **stamps)
  end

  def map_seed_jsonb
    json = { 'z' => 'first', 'long_key' => 'last', 'aa' => 'middle', 'nested' => { 'b' => 'B', 'longer' => 'X' },
             'array' => [{ 'zz' => 2, 'a' => 1 }], 'float' => 2.50, 'big' => 12_345_678_901_234 }
    value = ActiveRecord::Base.connection.quote(JSON.generate(json))
    ActiveRecord::Base.connection.execute(
      "UPDATE points SET geodata = #{value}, motion_data = #{value} WHERE id = 870001"
    )
  end

  def map_seed_degenerate
    [30, 31].each do |offset|
      map_insert('points', id: 870_400 + offset, user_id: ApiMapGoldenOracle::OWNER, track_id: 830_001,
                           timestamp: ApiMapGoldenOracle::T0 + offset, lonlat: 'SRID=4326;POINT(13.0005 52.0005)',
                           import_id: 820_005, created_at: ApiMapGoldenOracle::STAMP,
                           updated_at: ApiMapGoldenOracle::STAMP)
    end
  end

  def map_seed_null_geometry
    map_insert('points', id: 870_301, user_id: ApiMapGoldenOracle::OWNER, timestamp: ApiMapGoldenOracle::T0 + 7200,
                         lonlat: nil, created_at: ApiMapGoldenOracle::STAMP, updated_at: ApiMapGoldenOracle::STAMP)
  end
end
