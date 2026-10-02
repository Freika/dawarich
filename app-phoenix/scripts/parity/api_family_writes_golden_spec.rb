# frozen_string_literal: true

require 'rails_helper'
require_relative 'family_golden_headers'

module ApiFamilyWritesOracle
  TABLES = %w[users families family_memberships family_location_requests notifications points].freeze
  AFTER = %w[users family_location_requests notifications].freeze
  OWNER = 890_001
  MEMBER = 890_002
  STRANGER = 890_003
  GONE = 890_004
  FAMILY = 891_001
  KEY = 'phoenix-a4fam-writes-key'
  NOW = Time.utc(2037, 1, 15, 10, 30, 0)
  STAMP = '2029-12-01 08:00:00'
  SEQUENCES = { 'family_location_requests_id_seq' => 895_000, 'notifications_id_seq' => 896_000 }.freeze
  F = '/api/v1/families'
  R = "#{F}/location_requests".freeze
  SHARE = { 'enabled' => true, 'started_at' => '2037-01-12T10:30:00Z', 'share_history' => true,
            'history_window' => '7d' }.freeze
  MINE_SHARE = { 'enabled' => true, 'duration' => '6h', 'expires_at' => '2037-01-15T14:00:00Z',
                 'started_at' => '2037-01-15T08:00:00+01:00', 'share_history' => true,
                 'history_window' => '30d', 'history_before_sharing' => true }.freeze
  INCOMING = { id: 892_001, requester: MEMBER, target: OWNER, created: -600, expires: 86_000 }.freeze
  OUTGOING = { id: 892_002, requester: OWNER, target: MEMBER, created: -1200, expires: 85_000 }.freeze
  STALE = [{ id: 892_003, requester: MEMBER, target: OWNER, created: -90_000, expires: -3600 },
           { id: 892_004, requester: MEMBER, target: OWNER, status: 2, created: -700, expires: 86_000 }].freeze
  RANGE = 'start_at=2037-01-05T00:00:00Z&end_at=2037-01-15T10:30:00Z'
  H = "#{F}/locations/history?#{RANGE}".freeze
  JSON_TYPE = { 'Content-Type' => 'application/json' }.freeze
  FORM = { 'Content-Type' => 'application/x-www-form-urlencoded' }.freeze
  CASES = [
    { name: 'mine_full', path: "#{F}/mine", actor: { timezone: 'Europe/Berlin', share: MINE_SHARE },
      requests: [INCOMING, OUTGOING, *STALE] },
    { name: 'mine_defaults', path: "#{F}/mine", actor: { share: nil } },
    { name: 'mine_falsey_values', path: "#{F}/mine",
      actor: { share: { 'enabled' => false, 'duration' => false, 'history_window' => false } } },
    { name: 'mine_member_history_hidden', path: "#{F}/mine", member: { share: SHARE.merge('enabled' => false) } },
    { name: 'mine_not_in_family', path: "#{F}/mine", seed: :no_family },
    { name: 'history_member_window', path: H, points: true },
    { name: 'history_before_sharing_all', path: H, points: true,
      member: { share: SHARE.merge('history_before_sharing' => true, 'history_window' => 'all') } },
    { name: 'history_window_24h', path: H, points: true, member: { share: SHARE.merge('history_window' => '24h') } },
    { name: 'history_window_unknown', path: H, points: true,
      member: { share: SHARE.merge('history_window' => '2w', 'started_at' => nil, 'history_before_sharing' => true) } },
    { name: 'history_date_only_berlin', path: "#{F}/locations/history?start_at=2037-01-13&end_at=2037-01-15",
      points: true, actor: { timezone: 'Europe/Berlin' } },
    { name: 'history_offset_params', points: true,
      path: "#{F}/locations/history?start_at=2037-01-14T00:00:00%2B05:00&end_at=2037-01-15T09:00:00.5Z" },
    { name: 'history_share_history_off', path: H, points: true,
      member: { share: SHARE.merge('share_history' => false) } },
    { name: 'history_no_start_no_consent', path: H, points: true, member: { share: SHARE.merge('started_at' => '') } },
    { name: 'history_empty_range', path: "#{F}/locations/history?start_at=2037-01-15T10:30:00Z&end_at=2037-01-15",
      points: true },
    { name: 'history_missing_params', path: "#{F}/locations/history?start_at=2037-01-01" },
    { name: 'history_blank_params', path: "#{F}/locations/history?start_at=%20&end_at=" },
    { name: 'history_not_in_family', path: H, seed: :no_family },
    { name: 'sharing_enable_hour', method: :patch, path: "#{F}/sharing", actor: { timezone: 'Europe/Berlin' },
      body: { enabled: true, duration: '1h' } },
    { name: 'sharing_enable_permanent', method: :patch, path: "#{F}/sharing",
      body: { enabled: true, duration: 'permanent', share_history: true, history_window: '24h' } },
    { name: 'sharing_enable_carry_future', method: :patch, path: "#{F}/sharing", actor: { timezone: 'Asia/Tokyo',
      share: { 'enabled' => false, 'duration' => '24h', 'expires_at' => '2037-01-15T20:00:00Z',
               'started_at' => 'kept-as-is' } }, body: { enabled: true } },
    { name: 'sharing_enable_carry_past', method: :patch, path: "#{F}/sharing",
      actor: { share: { 'duration' => '12h', 'expires_at' => '2037-01-15T09:00:00Z', 'share_history' => true,
                        'history_before_sharing' => true } }, body: { enabled: true } },
    { name: 'sharing_form_strings', method: :patch, path: "#{F}/sharing", content: FORM,
      body: 'enabled=1&duration=6h&share_history=true&history_window=all&history_before_sharing=1' },
    { name: 'sharing_put', method: :put, path: "#{F}/sharing", body: { enabled: 'true', duration: '12h' } },
    { name: 'sharing_blank_flags', method: :patch, path: "#{F}/sharing",
      actor: { share: { 'enabled' => false, 'share_history' => true, 'history_window' => '30d' } },
      body: { enabled: true, duration: '', share_history: '', history_before_sharing: '' } },
    { name: 'sharing_consent_needs_history', method: :patch, path: "#{F}/sharing",
      body: { enabled: true, share_history: 'false', history_before_sharing: true } },
    { name: 'sharing_disable', method: :patch, path: "#{F}/sharing", actor: { share: MINE_SHARE },
      body: { enabled: 'off' } },
    { name: 'sharing_disable_unchanged', method: :patch, path: "#{F}/sharing", actor: { share: { 'enabled' => false } },
      body: { enabled: false } },
    { name: 'sharing_missing_enabled', method: :patch, path: "#{F}/sharing", body: { duration: '1h' } },
    { name: 'sharing_blank_enabled', method: :patch, path: "#{F}/sharing", body: { enabled: '  ' } },
    { name: 'sharing_not_in_family', method: :patch, path: "#{F}/sharing", seed: :no_family, body: { enabled: true } },
    { name: 'create_request', method: :post, path: R, actor: { timezone: 'Europe/Berlin' },
      member: { share: nil, locale: 'de' }, mask: ['"expires_at":"[^"]*"'], body: { target_user_id: MEMBER } },
    { name: 'create_request_string_id', method: :post, path: R, member: { share: nil },
      requests: [{ id: 892_005, requester: OWNER, target: MEMBER, created: -7200, expires: 79_000 }],
      body: { target_user_id: MEMBER.to_s } },
    { name: 'create_target_sharing', method: :post, path: R, body: { target_user_id: MEMBER } },
    { name: 'create_cooldown', method: :post, path: R, member: { share: nil }, requests: [OUTGOING],
      body: { target_user_id: MEMBER } },
    { name: 'create_cooldown_boundary', method: :post, path: R, member: { share: nil },
      requests: [OUTGOING.merge(created: -3600)], body: { target_user_id: MEMBER } },
    { name: 'create_stranger', method: :post, path: R, body: { target_user_id: STRANGER } },
    { name: 'create_deleted_member', method: :post, path: R, body: { target_user_id: GONE } },
    { name: 'create_without_target', method: :post, path: R, body: {} },
    { name: 'create_not_in_family', method: :post, path: R, seed: :no_family, body: { target_user_id: MEMBER } },
    { name: 'accept_suggested', method: :post, path: "#{R}/892001/accept", requests: [INCOMING],
      actor: { timezone: 'America/New_York' } },
    { name: 'accept_duration', method: :post, path: "#{R}/892001/accept", requests: [INCOMING],
      actor: { share: { 'enabled' => false, 'started_at' => '2029-01-01T00:00:00Z' } }, body: { duration: '6h' } },
    { name: 'decline', method: :post, path: "#{R}/892001/decline", requests: [INCOMING] },
    { name: 'accept_not_target', method: :post, path: "#{R}/892002/accept", requests: [OUTGOING] },
    { name: 'accept_expired', method: :post, path: "#{R}/892003/accept", requests: STALE },
    { name: 'decline_declined', method: :post, path: "#{R}/892004/decline", requests: STALE },
    { name: 'accept_expiring_now', method: :post, path: "#{R}/892001/accept", requests: [INCOMING.merge(expires: 0)] },
    { name: 'accept_missing', method: :post, path: "#{R}/892999/accept", requests: [INCOMING] },
    { name: 'replay_mine_sharing_string', expect: :rails, path: "#{F}/mine", actor: { share: 'on' } },
    { name: 'replay_mine_deleted_requester', expect: :rails, path: "#{F}/mine",
      requests: [INCOMING.merge(requester: GONE)] },
    { name: 'replay_mine_loose_started', expect: :rails, path: "#{F}/mine",
      actor: { share: { 'enabled' => false, 'started_at' => '2037-01-01' } } },
    { name: 'replay_history_loose_date', expect: :rails,
      path: "#{F}/locations/history?start_at=Jan%205%202037&end_at=x" },
    { name: 'replay_history_epoch', expect: :rails,
      path: "#{F}/locations/history?start_at=1893456000&end_at=1893456001" },
    { name: 'replay_history_array', expect: :rails, path: "#{F}/locations/history?start_at[]=a&end_at=2037-01-15" },
    { name: 'replay_sharing_numeric_duration', expect: :rails, method: :patch, path: "#{F}/sharing",
      body: { enabled: true, duration: '48' } },
    { name: 'replay_sharing_integer_enabled', expect: :rails, method: :patch, path: "#{F}/sharing",
      body: { enabled: 1 } },
    { name: 'replay_sharing_immich_slash', expect: :rails, method: :patch, path: "#{F}/sharing",
      actor: { extra: { 'immich_url' => 'https://immich.example.invalid/' } }, body: { enabled: false } },
    { name: 'replay_sharing_blank_email', expect: :rails, method: :patch, path: "#{F}/sharing",
      actor: { email: '' }, body: { enabled: false } },
    { name: 'replay_sharing_string_config', expect: :rails, method: :patch, path: "#{F}/sharing",
      actor: { share: 'on' }, body: { enabled: true } },
    { name: 'replay_create_self', expect: :rails, method: :post, path: R, actor: { share: nil },
      body: { target_user_id: OWNER } },
    { name: 'replay_create_junk_id', expect: :rails, method: :post, path: R, body: { target_user_id: '890002abc' } },
    { name: 'replay_create_loose_target_expiry', expect: :rails, method: :post, path: R,
      member: { share: SHARE.merge('expires_at' => 'nonsense') }, body: { target_user_id: MEMBER } },
    { name: 'replay_accept_loose_suggestion', expect: :rails, method: :post, path: "#{R}/892001/accept",
      requests: [INCOMING.merge(suggested: '48h')] },
    { name: 'rails_accept_id_shape', expect: :rails, method: :post, path: "#{R}/abc/accept", auth: :none },
    { name: 'rails_mine_head', expect: :rails, method: :head, path: "#{F}/mine", auth: :none },
    { name: 'rails_history_json_suffix', expect: :rails, path: "#{F}/locations/history.json", auth: :none },
    { name: 'rails_sharing_post', expect: :rails, method: :post, path: "#{F}/sharing", auth: :none },
    { name: 'rails_cloud_create', expect: :rails, method: :post, path: R, env: { 'SELF_HOSTED' => 'false' },
      body: { target_user_id: MEMBER } },
    { name: 'rails_kill_switch_sharing', expect: :rails, method: :patch, path: "#{F}/sharing",
      env: { 'DAWARICH_RAILS_SLICES' => 'api_family' }, body: { enabled: false } }
  ].freeze

  def self.results
    @results ||= []
  end

  def self.setups
    @setups ||= {}
  end
end

require_relative 'family_writes_golden_support'

RSpec.describe 'Phoenix fixture: golden family API writes', type: :request do
  include ActiveSupport::Testing::TimeHelpers
  include FamilyWritesGoldenSupport

  after(:all) do
    path = Rails.root.join('app-phoenix/test/fixtures/api_family/writes.json')
    oracle = ApiFamilyWritesOracle
    fixture = { 'time_zone' => ENV.fetch('TIME_ZONE', nil), 'now' => oracle::NOW.iso8601,
                'sequences' => oracle::SEQUENCES, 'setups' => oracle.setups.sort.to_h,
                'cases' => oracle.results.sort_by { _1['name'] } }
    File.write(path, "#{writes_exact_json(fixture)}\n")
  end

  ApiFamilyWritesOracle::CASES.each do |kase|
    it(kase[:name]) do
      defaults = { method: :get, auth: :bearer, expect: :own, env: {}, seed: :base, content: ApiFamilyWritesOracle::JSON_TYPE }
      ApiFamilyWritesOracle.results << writes_record(kase.reverse_merge(defaults))
    end
  end
end
