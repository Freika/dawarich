# frozen_string_literal: true

require 'rails_helper'

module ApiFamilyGoldenOracle
  TABLES = %w[users families family_memberships point_sources points].freeze
  OWNER = 880_001
  MEMBER = 880_002
  STRANGER = 880_003
  GONE = 880_004
  FAMILY = 881_001
  KEY = 'phoenix-a4fam-golden-key'
  STAMP = '2026-09-01 12:00:00'
  T0 = 1_780_000_000
  L = '/api/v1/families/locations'
  FUTURE = '2099-01-01T00:00:00Z'
  NOW_MASK = ['"updated_at":"[^"]*","sharing_enabled"'].freeze
  ACCEPT = { json: { 'Accept' => 'application/json' }, any: { 'Accept' => '*/*' }, none: {},
             xml: { 'Accept' => 'application/xml' } }.freeze
  CASES = [
    { name: 'locations_member_shares', path: L },
    { name: 'locations_both_share', path: L, actor: { share: {} } },
    { name: 'locations_no_points', path: L, seed: :no_points },
    { name: 'locations_not_in_family', path: L, seed: :no_family },
    { name: 'locations_member_disabled', path: L, share: { 'enabled' => false } },
    { name: 'locations_enabled_string', path: L, share: { 'enabled' => 'true' } },
    { name: 'locations_enabled_one', path: L, share: { 'enabled' => 1 } },
    { name: 'locations_sharing_string', path: L, member_settings: { 'family' => { 'location_sharing' => 'on' } } },
    { name: 'locations_sharing_array', path: L, member_settings: { 'family' => { 'location_sharing' => [] } } },
    { name: 'locations_family_absent', path: L, member_settings: { 'timezone' => 'UTC' } },
    { name: 'locations_family_null', path: L, member_settings: { 'family' => nil } },
    { name: 'locations_expiry_future', path: L, share: { 'expires_at' => FUTURE } },
    { name: 'locations_expiry_offset_fraction', path: L, share: { 'expires_at' => '2099-01-01T00:00:00.5+01:00' } },
    { name: 'locations_expiry_past', path: L, share: { 'expires_at' => '2001-01-01T00:00:00+02:00' } },
    { name: 'locations_expiry_empty', path: L, share: { 'expires_at' => '' } },
    { name: 'locations_expiry_spaces', path: L, share: { 'expires_at' => " \t " } },
    { name: 'locations_expiry_null', path: L, share: { 'expires_at' => nil } },
    { name: 'locations_expiry_false', path: L, share: { 'expires_at' => false } },
    { name: 'locations_actor_expired', path: L, actor: { share: { 'expires_at' => '2001-01-01T00:00:00Z' } } },
    { name: 'locations_newest_anomaly_skipped', path: L, point: { anomaly: true } },
    { name: 'locations_null_anomaly_counts', path: L, point: { anomaly: nil } },
    { name: 'locations_null_timestamp_skipped', path: L, point: { timestamp: nil } },
    { name: 'locations_null_geometry_skipped', path: L, point: { lonlat: nil } },
    { name: 'locations_null_battery', path: L, point: { battery: nil, battery_status: nil } },
    { name: 'locations_unknown_battery_status', path: L, point: { battery_status: 7 } },
    { name: 'locations_dimension_status', path: L, point: { source_id: 882_001 } },
    { name: 'locations_dimension_null_status', path: L, point: { source_id: 882_002 } },
    { name: 'locations_unicode_email', path: L, member: { email: 'élise@example.invalid' } },
    { name: 'locations_zone_berlin', path: L, actor: { timezone: 'Europe/Berlin', share: {} } },
    { name: 'locations_zone_new_york', path: L, actor: { timezone: 'America/New_York' } },
    { name: 'locations_zone_rails_name', path: L, actor: { timezone: 'Berlin' } },
    { name: 'locations_query_key', path: L, auth: :query },
    { name: 'locations_no_accept', path: L, accept: :none },
    { name: 'locations_accept_any', path: L, accept: :any },
    { name: 'locations_accept_xml', path: L, accept: :xml },
    { name: 'locations_accept_language', path: L, headers: { 'Accept-Language' => 'de' } },
    { name: 'locations_inactive_user', path: L, actor: { status: 0 } },
    { name: 'locations_expired_user', path: L, actor: { active_until: '2001-01-01 00:00:00' } },
    { name: 'auth_none_locations', path: L, auth: :none },
    { name: 'auth_unknown_locations', path: L, auth: :unknown },
    { name: 'auth_pending_locations', path: L, actor: { status: 3 } },
    { name: 'replay_expiry_unparsable', expect: :rails, path: L, share: { 'expires_at' => 'nonsense' } },
    { name: 'replay_expiry_date_only', expect: :rails, path: L, share: { 'expires_at' => '2099-01-01' } },
    { name: 'replay_expiry_without_offset', expect: :rails, path: L, share: { 'expires_at' => '2099-01-01T00:00' } },
    { name: 'replay_expiry_true', expect: :rails, path: L, share: { 'expires_at' => true } },
    { name: 'replay_expiry_nanoseconds', expect: :rails, path: L,
      share: { 'expires_at' => '2099-01-01T00:00:00.1234567Z' } },
    { name: 'replay_expiry_space_separator', expect: :rails, path: L,
      share: { 'expires_at' => '2099-01-01 00:00:00Z' } },
    { name: 'replay_family_string', expect: :rails, path: L, member_settings: { 'family' => 'x' } },
    { name: 'replay_member_settings_null', expect: :rails, path: L, member_settings: :null },
    { name: 'replay_actor_expiry_unparsable', expect: :rails, path: L, actor: { share: { 'expires_at' => 'x' } } },
    { name: 'replay_unknown_zone', expect: :rails, path: L, actor: { timezone: 'Mars/Olympus' } },
    { name: 'rails_locations_head', expect: :rails, method: :head, path: L, auth: :none },
    { name: 'rails_locations_json_suffix', expect: :rails, path: "#{L}.json", auth: :none },
    { name: 'rails_cloud_locations', expect: :rails, path: L, env: { 'SELF_HOSTED' => 'false' } },
    { name: 'rails_kill_switch_locations', expect: :rails, path: L, env: { 'DAWARICH_RAILS_SLICES' => 'api_family' } }
  ].freeze

  def self.results
    @results ||= []
  end

  def self.setups
    @setups ||= {}
  end
end

RSpec.describe 'Phoenix fixture: golden family API requests', type: :request do
  after(:all) do
    path = Rails.root.join('app-phoenix/test/fixtures/api_family/golden.json')
    FileUtils.mkdir_p(path.dirname)
    fixture = { 'time_zone' => ENV.fetch('TIME_ZONE', nil), 'setups' => ApiFamilyGoldenOracle.setups.sort.to_h,
                'cases' => ApiFamilyGoldenOracle.results.sort_by { _1['name'] } }
    File.write(path, "#{family_exact_json(fixture)}\n")
  end

  ApiFamilyGoldenOracle::CASES.each do |kase|
    it(kase[:name]) do
      defaults = { method: :get, auth: :bearer, accept: :json, expect: :own, env: {}, seed: :base }
      ApiFamilyGoldenOracle.results << family_record(kase.reverse_merge(defaults))
    end
  end

  def family_exact_json(value, depth = 0)
    pad = '  ' * (depth + 1)
    case value
    when Hash
      return '{}' if value.empty?

      entries = value.map { |k, v| "#{pad}#{Oj.dump(k.to_s, mode: :strict)}: #{family_exact_json(v, depth + 1)}" }
      "{\n#{entries.join(",\n")}\n#{'  ' * depth}}"
    when Array
      return '[]' if value.empty?

      "[\n#{value.map { |v| "#{pad}#{family_exact_json(v, depth + 1)}" }.join(",\n")}\n#{'  ' * depth}]"
    when Float
      value.to_s
    else
      Oj.dump(value, mode: :strict)
    end
  end

  def family_record(kase)
    family_seed(kase)
    allow(DawarichSettings).to receive(:self_hosted?).and_return(false) if kase[:env]['SELF_HOSTED'] == 'false'
    headers = family_headers(kase)
    path = kase[:auth] == :query ? "#{kase[:path]}?api_key=#{ApiFamilyGoldenOracle::KEY}" : kase[:path]
    setup = family_setup
    response = family_response(kase, path, headers)
    raise "#{kase[:name]} wrote rows" unless family_setup == setup

    mask = kase[:expect] == :own && response['status'] == 200 ? ApiFamilyGoldenOracle::NOW_MASK : []
    { 'name' => kase[:name], 'expect' => kase[:expect].to_s, 'ignore' => mask.empty? ? [] : ['etag'],
      'mask' => mask, 'unordered' => mask.empty? ? [] : ['locations'], 'env' => kase[:env], 'setup' => setup,
      'request' => { 'method' => kase[:method].to_s.upcase, 'target' => path, 'headers' => headers.to_a },
      'response' => response }
  end

  def family_response(kase, path, headers)
    send(kase[:method], path, headers: headers)
    headers = response.headers.to_h.transform_keys(&:downcase).except('date', 'content-length')
    body = kase[:expect] == :rails ? response.body.gsub(/token=[\w.-]+/, 'token=redacted') : response.body
    { 'status' => response.status, 'headers' => headers, 'body' => body }
  rescue StandardError
    raise unless kase[:expect] == :rails

    { 'status' => 500, 'headers' => {}, 'body' => '' }
  end

  def family_setup
    rows = ApiFamilyGoldenOracle::TABLES.map do |table|
      values = ActiveRecord::Base.connection.select_values("SELECT row_to_json(t)::text FROM #{table} t ORDER BY id")
      [table, values.map { JSON.parse(_1).compact }]
    end
    key = Digest::SHA256.hexdigest(JSON.generate(rows))[0, 16]
    ApiFamilyGoldenOracle.setups[key] = rows
    key
  end

  def family_headers(kase)
    headers = { 'Host' => 'localhost' }.merge(ApiFamilyGoldenOracle::ACCEPT.fetch(kase[:accept]))
                                       .merge(kase[:headers] || {})
    headers['Authorization'] = "Bearer #{ApiFamilyGoldenOracle::KEY}" if kase[:auth] == :bearer
    headers['Authorization'] = 'Bearer phoenix-a4fam-golden-unknown' if kase[:auth] == :unknown
    headers
  end

  def family_insert(table, row)
    connection = ActiveRecord::Base.connection
    columns = row.keys.map { connection.quote_column_name(_1) }.join(', ')
    values = row.values.map { connection.quote(_1.is_a?(Hash) || _1.is_a?(Array) ? JSON.generate(_1) : _1) }
    connection.execute("INSERT INTO #{table} (#{columns}) VALUES (#{values.join(', ')})")
  end

  def family_sharing(extra)
    { 'enabled' => true, 'started_at' => '2026-09-01T12:00:00Z', 'share_history' => false }.merge(extra)
  end

  def family_settings(timezone, share)
    settings = { 'timezone' => timezone }
    settings['family'] = { 'location_sharing' => family_sharing(share) } if share
    settings
  end

  def family_seed(kase)
    oracle = ApiFamilyGoldenOracle
    actor = { status: 1, active_until: nil, timezone: 'UTC', share: nil }.merge(kase[:actor] || {})
    member_settings = kase.fetch(:member_settings, family_settings('UTC', kase[:share] || {}))
    stamps = { created_at: oracle::STAMP, updated_at: oracle::STAMP }
    redetected = { visits_redetected_at: oracle::STAMP, **stamps }
    family_insert('users', id: oracle::OWNER, email: 'family-owner@example.invalid', api_key: oracle::KEY,
                           status: actor[:status], active_until: actor[:active_until],
                           settings: family_settings(actor[:timezone], actor[:share]), **redetected)
    family_insert('users', id: oracle::MEMBER, email: kase.dig(:member, :email) || 'family-member@example.invalid',
                           api_key: 'phoenix-a4fam-member', status: 1,
                           settings: member_settings == :null ? nil : member_settings, **redetected)
    family_insert('users', id: oracle::STRANGER, email: 'family-stranger@example.invalid',
                           api_key: 'phoenix-a4fam-stranger', status: 1,
                           settings: family_settings('UTC', {}), **redetected)
    family_insert('users', id: oracle::GONE, email: 'family-gone@example.invalid', api_key: 'phoenix-a4fam-gone',
                           status: 1, deleted_at: oracle::STAMP, settings: family_settings('UTC', {}), **redetected)
    family_seed_families(kase, stamps)
    family_seed_points(kase, stamps) unless kase[:seed] == :no_points
  end

  def family_seed_families(kase, stamps)
    oracle = ApiFamilyGoldenOracle
    family_insert('families', id: oracle::FAMILY, name: 'Leipzig household', creator_id: oracle::OWNER, **stamps)
    family_insert('families', id: oracle::FAMILY + 1, name: 'Other household', creator_id: oracle::STRANGER, **stamps)
    roles = [[oracle::OWNER, 0], [oracle::MEMBER, 1], [oracle::GONE, 1], [oracle::STRANGER, 0]]
    roles.each_with_index do |(id, role), i|
      next if id == oracle::OWNER && kase[:seed] == :no_family

      family = id == oracle::STRANGER ? oracle::FAMILY + 1 : oracle::FAMILY
      family_insert('family_memberships', id: 883_001 + i, family_id: family, user_id: id, role:, **stamps)
    end
  end

  def family_seed_points(kase, stamps)
    oracle = ApiFamilyGoldenOracle
    family_insert('point_sources', id: 882_001, digest: 'a' * 32, tracker_id: 'dimension', battery_status: 4, **stamps)
    family_insert('point_sources', id: 882_002, digest: 'b' * 32, tracker_id: 'dimension-null', **stamps)
    [oracle::OWNER, oracle::MEMBER, oracle::STRANGER, oracle::GONE].each_with_index do |user_id, i|
      base = { user_id:, battery: 60 + i, battery_status: 1, anomaly: false, **stamps }
      family_insert('points', id: 884_001 + (i * 10), timestamp: oracle::T0 + (i * 60),
                              lonlat: "SRID=4326;POINT(12.37#{i}123456789 51.33#{i}987654321)", **base)
      newest = { id: 884_002 + (i * 10), timestamp: oracle::T0 + 3600 + (i * 60),
                 lonlat: "SRID=4326;POINT(12.38#{i}5 51.34#{i}25)", **base, battery_status: 2 }
      newest.merge!(kase[:point]) if kase[:point] && user_id == oracle::MEMBER
      family_insert('points', newest)
    end
  end
end
