# frozen_string_literal: true

require 'rails_helper'

module ApiPlacesGoldenOracle
  TABLES = %w[users tags places taggings visits place_visits notes].freeze
  AFTER = %w[tags places taggings visits place_visits notes].freeze
  OWNER = 950_001
  OTHER = 950_002
  KEY = 'phoenix-a4pl-golden-key'
  NOW = Time.utc(2026, 10, 2, 12, 0, 0)
  STAMP = '2026-09-01 12:00:00'
  SEQUENCES = { 'places_id_seq' => 955_000 }.freeze
  P = '/api/v1/places'
  H = "#{P}/950201".freeze
  S = "#{P}/950202".freeze
  JSON_TYPE = { 'Content-Type' => 'application/json' }.freeze
  FORM = { 'Content-Type' => 'application/x-www-form-urlencoded' }.freeze
  LEIPZIG = { latitude: 51.3404, longitude: 12.3778 }.freeze
  CRLF = "#{'a' * 126}\r\n#{'b' * 127}".freeze
  BERLIN = { timezone: 'Europe/Berlin' }.freeze
  KILL = { 'DAWARICH_RAILS_SLICES' => 'api_places' }.freeze
  CASES = [
    { name: 'show_tagged', path: H },
    { name: 'show_active_visits', path: S },
    { name: 'show_legacy_geometry', path: "#{P}/950203" },
    { name: 'show_unicode', path: "#{P}/950206" },
    { name: 'show_zone_berlin', path: H, user: BERLIN },
    { name: 'show_zone_rails_name', path: H, user: { timezone: 'Berlin' } },
    { name: 'show_leading_zero', path: "#{P}/0950201" },
    { name: 'show_missing', path: "#{P}/959999" },
    { name: 'show_foreign', path: "#{P}/950204" },
    { name: 'show_if_none_match', path: H, conditional: true },
    { name: 'show_no_accept', path: H, accept: :none },
    { name: 'show_accept_xml', path: H, headers: { 'Accept' => 'application/xml' } },
    { name: 'show_query_key', path: H, auth: :query },
    { name: 'show_inactive_user', path: H, user: { status: 0 } },
    { name: 'auth_none_show', path: H, auth: :none },
    { name: 'auth_unknown_create', method: :post, path: P, auth: :unknown, body: { place: { name: 'X', **LEIPZIG } } },
    { name: 'auth_pending_create', method: :post, path: P, user: { status: 3 },
      body: { place: { name: 'X', **LEIPZIG } } },
    { name: 'index_default', path: P },
    { name: 'index_all', path: "#{P}?filter=all" },
    { name: 'index_manual', path: "#{P}?filter=manual" },
    { name: 'index_confirmed', path: "#{P}?filter=confirmed" },
    { name: 'index_tagged', path: "#{P}?filter=tagged" },
    { name: 'index_unknown_filter', path: "#{P}?filter=bogus" },
    { name: 'index_page', path: "#{P}?filter=all&page=1&per_page=2" },
    { name: 'index_page_two', path: "#{P}?filter=all&page=2&per_page=2" },
    { name: 'index_page_past_end', path: "#{P}?page=9&per_page=2" },
    { name: 'index_page_default_per', path: "#{P}?page=1" },
    { name: 'index_per_page_cap', path: "#{P}?filter=all&page=1&per_page=1000" },
    { name: 'index_per_page_without_page', path: "#{P}?per_page=2" },
    { name: 'index_zone_berlin', path: P, user: BERLIN },
    { name: 'index_empty', path: P, seed: :bare },
    { name: 'index_empty_page', path: "#{P}?page=1", seed: :bare },
    { name: 'create_custom_name', method: :post, path: P,
      body: { place: { name: 'Nikolaikirche', note: 'Leipzig', **LEIPZIG } } },
    { name: 'create_placeholder', method: :post, path: P,
      body: { place: { name: 'Suggested place', source: 'photon', latitude: 51.3397, longitude: 12.3731 } } },
    { name: 'create_string_coordinates', method: :post, path: P,
      body: { place: { name: 'Thomaskirche', source: 'gpx_waypoint', latitude: '51.3393', longitude: '12.3725' } } },
    { name: 'create_integer_coordinates', method: :post, path: P,
      body: { place: { name: 'Grid', latitude: 51, longitude: 12 } } },
    { name: 'create_ignores_unknown_keys', method: :post, path: P,
      body: { place: { name: 'Moritzbastei', city: 'Elsewhere', user_id: OTHER, **LEIPZIG }, extra: 1 } },
    { name: 'create_name_255_crlf', method: :post, path: P, body: { place: { name: CRLF, **LEIPZIG } } },
    { name: 'create_zone_berlin', method: :post, path: P, user: BERLIN,
      body: { place: { name: 'Augustusplatz', **LEIPZIG } } },
    { name: 'invalid_missing_name', method: :post, path: P, body: { place: LEIPZIG } },
    { name: 'invalid_whitespace_name', method: :post, path: P, body: { place: { name: " \t\n", **LEIPZIG } } },
    { name: 'invalid_long_name', method: :post, path: P, body: { place: { name: "#{CRLF}c", **LEIPZIG } } },
    { name: 'invalid_missing_coordinates', method: :post, path: P, body: { place: { name: 'Nowhere' } } },
    { name: 'invalid_one_coordinate', method: :post, path: P, body: { place: { name: 'Half', latitude: 51.34 } } },
    { name: 'invalid_null_coordinates', method: :post, path: P,
      body: { place: { name: 'Null', latitude: nil, longitude: nil } } },
    { name: 'invalid_everything', method: :post, path: P, body: { place: { note: 'only a note' } } },
    { name: 'update_partial_latitude', method: :patch, path: H,
      body: { place: { name: 'Leipzig Hbf', note: 'west hall', latitude: 51.3455 } } },
    { name: 'update_note_only', method: :patch, path: H, body: { place: { note: 'east hall' } } },
    { name: 'update_noop', method: :patch, path: H,
      body: { place: { name: 'Leipzig Hauptbahnhof', latitude: '51.345000', source: 'manual' } } },
    { name: 'update_unknown_keys_only', method: :patch, path: H, body: { place: { city: 'Elsewhere' } } },
    { name: 'update_suggested_clears_lock', method: :patch, path: H, body: { place: { name: 'Suggested place' } } },
    { name: 'update_locks_placeholder', method: :patch, path: S, body: { place: { name: 'Augustusplatz' } } },
    { name: 'update_put_source', method: :put, path: S, body: { place: { source: 'manual' } } },
    { name: 'update_longitude_string', method: :patch, path: H, body: { place: { longitude: '12.382' } } },
    { name: 'update_zone_berlin', method: :patch, path: H, user: BERLIN, body: { place: { note: 'zoned' } } },
    { name: 'invalid_update_blank_name', method: :patch, path: H, body: { place: { name: '' } } },
    { name: 'invalid_update_long_name', method: :patch, path: H, body: { place: { name: 'x' * 256 } } },
    { name: 'update_missing', method: :patch, path: "#{P}/959999", body: { place: { note: 'x' } } },
    { name: 'update_foreign', method: :patch, path: "#{P}/950204", body: { place: { note: 'x' } } },
    { name: 'destroy_linked', method: :delete, path: H },
    { name: 'destroy_active_visits', method: :delete, path: S },
    { name: 'destroy_legacy', method: :delete, path: "#{P}/950203" },
    { name: 'destroy_missing', method: :delete, path: "#{P}/959999" },
    { name: 'destroy_foreign', method: :delete, path: "#{P}/950204" },
    { name: 'replay_create_tag_ids', expect: :rails, method: :post, path: P,
      body: { place: { name: 'Tagged', tag_ids: [950_101], **LEIPZIG } } },
    { name: 'replay_create_empty_tag_ids', expect: :rails, method: :post, path: P,
      body: { place: { name: 'Untagged', tag_ids: [], **LEIPZIG } } },
    { name: 'replay_update_tag_ids', expect: :rails, method: :patch, path: H, body: { place: { tag_ids: [950_102] } } },
    { name: 'replay_create_unicode_name', expect: :rails, method: :post, path: P,
      body: { place: { name: 'Café Kandler', **LEIPZIG } } },
    { name: 'replay_create_unicode_note', expect: :rails, method: :post, path: P,
      body: { place: { name: 'Kandler', note: 'Straße', **LEIPZIG } } },
    { name: 'replay_create_precision', expect: :rails, method: :post, path: P,
      body: { place: { name: 'Precise', latitude: 51.33971234, longitude: 12.3731 } } },
    { name: 'replay_create_latitude_range', expect: :rails, method: :post, path: P,
      body: { place: { name: 'North', latitude: 91, longitude: 12.3731 } } },
    { name: 'replay_create_longitude_range', expect: :rails, method: :post, path: P,
      body: { place: { name: 'East', latitude: 51.3397, longitude: 181 } } },
    { name: 'replay_create_source_invalid', expect: :rails, method: :post, path: P,
      body: { place: { name: 'Bogus', source: 'bogus', **LEIPZIG } } },
    { name: 'replay_create_source_integer', expect: :rails, method: :post, path: P,
      body: { place: { name: 'Numbered', source: 1, **LEIPZIG } } },
    { name: 'replay_create_name_number', expect: :rails, method: :post, path: P,
      body: { place: { name: 123, **LEIPZIG } } },
    { name: 'replay_create_coordinate_text', expect: :rails, method: :post, path: P,
      body: { place: { name: 'Exponent', latitude: '5.13e1', longitude: '12.3731' } } },
    { name: 'replay_create_wrapped_params', expect: :rails, method: :post, path: P,
      body: { name: 'Wrapped', **LEIPZIG } },
    { name: 'replay_create_empty_place', expect: :rails, method: :post, path: P, body: { place: {} } },
    { name: 'replay_create_place_string', expect: :rails, method: :post, path: P, body: { place: 'Leipzig' } },
    { name: 'replay_create_form_body', expect: :rails, method: :post, path: P, content: FORM,
      body: 'place%5Bname%5D=Form&place%5Blatitude%5D=51.34&place%5Blongitude%5D=12.37' },
    { name: 'replay_update_null_latitude', expect: :rails, method: :patch, path: H,
      body: { place: { latitude: nil } } },
    { name: 'replay_update_legacy_geometry', expect: :rails, method: :patch, path: "#{P}/950203",
      body: { place: { note: 'x' } } },
    { name: 'replay_update_incoherent_geometry', expect: :rails, method: :patch, path: "#{P}/950205",
      body: { place: { note: 'x' } } },
    { name: 'replay_update_unicode_persisted', expect: :rails, method: :patch, path: "#{P}/950206",
      body: { place: { note: 'x' } } },
    { name: 'replay_update_empty_body', expect: :rails, method: :patch, path: H },
    { name: 'replay_show_unknown_zone', expect: :rails, path: H, user: { timezone: 'Mars/Olympus' } },
    { name: 'replay_create_client_header', expect: :rails, method: :post, path: P,
      headers: { 'X-Dawarich-Client' => 'ios' }, body: { place: { name: 'Client', **LEIPZIG } } },
    { name: 'replay_create_method_override', expect: :rails, method: :post, path: P,
      headers: { 'X-HTTP-Method-Override' => 'GET' }, body: { place: { name: 'Override', **LEIPZIG } } },
    { name: 'replay_unauthenticated_method_override', expect: :rails, method: :post, path: P, auth: :none,
      headers: { 'X-HTTP-Method-Override' => 'PATCH' } },
    { name: 'replay_index_tag_ids', expect: :rails, path: "#{P}?tag_ids=950101" },
    { name: 'replay_index_untagged', expect: :rails, path: "#{P}?tag_ids=untagged" },
    { name: 'replay_index_page_shape', expect: :rails, path: "#{P}?page=01" },
    { name: 'replay_index_per_page_shape', expect: :rails, path: "#{P}?page=1&per_page=05" },
    { name: 'replay_index_per_page_zero', expect: :rails, path: "#{P}?page=1&per_page=0" },
    { name: 'rails_show_head', expect: :rails, method: :head, path: H, auth: :none },
    { name: 'rails_cloud_create', expect: :rails, method: :post, path: P, env: { 'SELF_HOSTED' => 'false' },
      body: { place: { name: 'Cloud', **LEIPZIG } } },
    { name: 'rails_kill_switch_destroy', expect: :rails, method: :delete, path: H, env: KILL },
    { name: 'rails_kill_switch_index', expect: :rails, path: P, env: KILL },
    { name: 'rails_kill_switch_show', expect: :rails, path: H, env: KILL },
    { name: 'rails_kill_switch_create', expect: :rails, method: :post, path: P, env: KILL,
      body: { place: { name: 'Handed back', **LEIPZIG } } },
    { name: 'rails_kill_switch_patch', expect: :rails, method: :patch, path: H, env: KILL,
      body: { place: { note: 'handed back' } } },
    { name: 'rails_kill_switch_put', expect: :rails, method: :put, path: H, env: KILL,
      body: { place: { note: 'handed back' } } },
    { name: 'rails_show_json_suffix', expect: :rails, path: "#{H}.json", auth: :none },
    { name: 'rails_id_shape', expect: :rails, path: "#{P}/abc", auth: :none },
    { name: 'rails_id_too_long', expect: :rails, path: "#{P}/1234567890123456789", auth: :none },
    { name: 'rails_nearby', expect: :rails, path: "#{P}/nearby?latitude=51.34&longitude=12.37", auth: :none },
    { name: 'rails_search', expect: :rails, path: "#{P}/search?lat=51.34&lon=12.37", auth: :none },
    { name: 'rails_post_member', expect: :rails, method: :post, path: H, auth: :none }
  ].freeze
  CLOSURE_CASES = [
    { name: 'closure_nearby_missing', path: "#{P}/nearby" },
    { name: 'closure_nearby_zero', path: "#{P}/nearby?latitude=0&longitude=0" },
    { name: 'closure_search_missing', path: "#{P}/search" },
    { name: 'closure_search_range', path: "#{P}/search?lat=91&lon=0" },
    { name: 'closure_search_saved', path: "#{P}/search?lat=51.34&lon=12.37&q=Leipzig" },
    { name: 'closure_create_invalid_source', expect: :rails, method: :post, path: P,
      body: { place: { name: 'Invalid source', source: 'invalid', **LEIPZIG } } },
    { name: 'closure_create_nested_name', method: :post, path: P,
      body: { place: { name: [], **LEIPZIG } } },
    { name: 'closure_create_scalar_tag', method: :post, path: P,
      body: { place: { name: 'Scalar tag', tag_ids: '950101', **LEIPZIG } } },
    { name: 'closure_create_unicode_tags', method: :post, path: P,
      body: { place: { name: 'Café', note: 'Straße', tag_ids: [950_101, 950_103], **LEIPZIG } } }
  ].freeze

  def self.results
    @results ||= []
  end

  def self.setups
    @setups ||= {}
  end
end

require_relative 'places_golden_support'

RSpec.describe 'Phoenix fixture: golden places API requests', type: :request do
  include ActiveSupport::Testing::TimeHelpers
  include PlacesGoldenSupport

  after(:all) do
    path = Rails.root.join('app-phoenix/test/fixtures/api_places/golden.json')
    FileUtils.mkdir_p(path.dirname)
    oracle = ApiPlacesGoldenOracle
    fixture = { 'time_zone' => ENV.fetch('TIME_ZONE', nil), 'now' => oracle::NOW.iso8601,
                'sequences' => oracle::SEQUENCES, 'setups' => oracle.setups.sort.to_h,
                'cases' => oracle.results.reject { _1['name'].start_with?('closure_') }.sort_by { _1['name'] } }
    File.write(path, "#{places_exact_json(fixture)}\n")
    closure_path = Rails.root.join('app-phoenix/test/fixtures/a12f2b/closure.json')
    FileUtils.mkdir_p(closure_path.dirname)
    closure = closure_path.exist? ? JSON.parse(closure_path.read) : {}
    closure['places'] = oracle.results.select { _1['name'].start_with?('closure_') }.sort_by { _1['name'] }
    File.write(closure_path, "#{places_exact_json(closure.sort.to_h)}\n")
  end

  (ApiPlacesGoldenOracle::CASES + ApiPlacesGoldenOracle::CLOSURE_CASES).each do |kase|
    it(kase[:name]) do
      defaults = { method: :get, auth: :bearer, expect: :own, env: {}, seed: :base,
                   content: ApiPlacesGoldenOracle::JSON_TYPE }
      if kase[:name].start_with?('closure_')
        ActiveRecord::Base.connection.execute("SELECT setval('taggings_id_seq', 959000, false)")
      end
      ApiPlacesGoldenOracle.results << places_record(kase.reverse_merge(defaults))
      expect(enqueued_jobs).to be_empty if kase.fetch(:expect, :own) == :own
    end
  end
end
