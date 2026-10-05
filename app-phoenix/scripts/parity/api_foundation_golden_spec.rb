# frozen_string_literal: true

require 'rails_helper'
require_relative 'fixture_recording'

module ApiFoundationGoldenOracle
  PLAN = '/api/v1/plan'
  JSON_ACCEPT = { 'Accept' => 'application/json' }.freeze
  DEFAULTS = { plan: 'pro', status: 'active', subscription_source: 'none',
               active_until: Time.utc(3026, 7, 1, 12), timezone: 'Europe/Berlin' }.freeze
  CASES = [
    { name: 'plan_mobile_bearer_json', headers: JSON_ACCEPT },
    { name: 'plan_query_key_no_accept', auth: :query,
      user: { active_until: Time.utc(2027, 1, 15, 10), timezone: :absent } },
    { name: 'plan_zone_utc', user: { active_until: Time.utc(2026, 12, 1, 10), timezone: 'UTC' } },
    { name: 'plan_zone_etc_utc', user: { active_until: Time.utc(2026, 12, 1, 10), timezone: 'Etc/UTC' } },
    { name: 'plan_zone_london_winter', user: { active_until: Time.utc(2027, 1, 15, 10), timezone: 'Europe/London' } },
    { name: 'plan_zone_berlin_summer', user: { active_until: Time.utc(2027, 7, 1, 10) } },
    { name: 'plan_zone_sydney_far', user: { timezone: 'Australia/Sydney' } },
    { name: 'plan_zone_kolkata_fraction',
      user: { active_until: Time.utc(2027, 3, 1, 10, 0, 0, 987_654), timezone: 'Asia/Kolkata' } },
    { name: 'plan_zone_new_york', user: { active_until: Time.utc(2027, 1, 15, 10), timezone: 'America/New_York' } },
    { name: 'plan_active_until_null', user: { active_until: nil } },
    { name: 'plan_lite_trial_apple_iap', user: { plan: 'lite', status: 'trial', subscription_source: 'apple_iap' } },
    { name: 'plan_family_google_play', user: { plan: 'family', subscription_source: 'google_play' } },
    { name: 'plan_pending_payment', headers: JSON_ACCEPT,
      user: { status: 'pending_payment', subscription_source: 'paddle' } },
    { name: 'plan_inactive', user: { status: 'inactive' } },
    { name: 'plan_expired', user: { active_until: Time.utc(2001, 1, 1) } },
    { name: 'plan_status_null', user: { status: nil } },
    { name: 'plan_format_param', path: "#{PLAN}?format=json", headers: { 'Accept' => 'text/html' } },
    { name: 'plan_if_none_match_hit', headers: JSON_ACCEPT, if_none_match: :hit },
    { name: 'plan_if_none_match_miss', headers: JSON_ACCEPT.merge('If-None-Match' => 'W/"0"') },
    { name: 'plan_request_id_valid', headers: { 'X-Request-Id' => 'phoenix-a4-req_1@golden' } },
    { name: 'plan_request_id_sanitized', headers: { 'X-Request-Id' => "bad id/<x>#{'a' * 300}" } },
    { name: 'auth_missing', auth: :none },
    { name: 'auth_unknown_accept_json', auth: :unknown, headers: JSON_ACCEPT },
    { name: 'auth_deleted', user: { deleted_at: Time.utc(2026, 1, 1) } },
    { name: 'auth_blank_param_beats_bearer', path: "#{PLAN}?api_key=" },
    { name: 'replay_zone_rails_alias', expect: :own, user: { timezone: 'Berlin' } },
    { name: 'replay_zone_case', expect: :rails, user: { timezone: 'europe/berlin' } },
    { name: 'replay_zone_integer', expect: :rails, user: { timezone: 1 } },
    { name: 'replay_client_header', expect: :rails, headers: { 'X-Dawarich-Client' => 'ios' },
      ignore: ['set-cookie'] },
    { name: 'replay_accept_png', expect: :rails, headers: { 'Accept' => 'image/png' } },
    { name: 'rails_head_plan', expect: :rails, method: :head },
    { name: 'rails_plan_json_suffix', expect: :rails, path: '/api/v1/plan.json' },
    { name: 'rails_cloud_plan', expect: :rails, env: { 'SELF_HOSTED' => 'false' }, user: { plan: 'lite' } },
    { name: 'rails_health_anonymous', expect: :rails, path: '/api/v1/health', auth: :none },
    { name: 'rails_health_bearer', expect: :rails, path: '/api/v1/health' },
    { name: 'rails_health_pending_payment', expect: :rails, path: '/api/v1/health', headers: JSON_ACCEPT,
      user: { status: 'pending_payment' } },
    { name: 'rails_health_unknown_key', expect: :rails, path: '/api/v1/health', auth: :unknown },
    { name: 'rails_ready_anonymous', expect: :rails, path: '/api/v1/ready', auth: :none },
    { name: 'rails_ready_pending_payment', expect: :rails, path: '/api/v1/ready', user: { status: 'pending_payment' } }
  ].freeze

  def self.results
    @results ||= []
  end
end

RSpec.describe 'Phoenix fixture: golden API foundation requests', type: :request do
  let(:fixture_models) { [User] }
  include FixtureRecording::DeterministicInputs
  before { JobHealth.reset! }

  after(:all) do
    path = Rails.root.join('app-phoenix/test/fixtures/api_foundation/golden.json')
    FileUtils.mkdir_p(path.dirname)
    fixture = { 'time_zone' => ENV.fetch('TIME_ZONE', nil),
                'cases' => ApiFoundationGoldenOracle.results.sort_by { _1['name'] } }
    File.write(path, "#{Oj.dump(fixture, mode: :strict, float_precision: 0, indent: 2)}\n")
  end

  ApiFoundationGoldenOracle::CASES.each do |kase|
    it(kase[:name]) do
      defaults = { method: :get, path: ApiFoundationGoldenOracle::PLAN, auth: :bearer, expect: :own, env: {} }
      ApiFoundationGoldenOracle.results << record(kase.reverse_merge(defaults))
    end
  end

  def user_for(kase)
    attrs = ApiFoundationGoldenOracle::DEFAULTS.merge(kase[:user] || {})
    user = create(:user)
    settings = if attrs[:timezone] == :absent
                 user.settings.except('timezone')
               else
                 user.settings.merge('timezone' => attrs[:timezone])
               end
    user.update_columns(api_key: "phoenix-a4-golden-key-#{kase[:name]}", plan: User.plans.fetch(attrs[:plan]),
                        status: attrs[:status] && User.statuses.fetch(attrs[:status]),
                        subscription_source: User.subscription_sources.fetch(attrs[:subscription_source]),
                        active_until: attrs[:active_until], settings:, deleted_at: attrs[:deleted_at])
    user
  end

  def record(kase)
    user = user_for(kase)
    allow(DawarichSettings).to receive(:self_hosted?).and_return(false) if kase[:env]['SELF_HOSTED'] == 'false'
    headers = { 'Host' => 'localhost' }.merge(kase[:headers] || {})
    headers['Authorization'] = "Bearer #{user.api_key}" if kase[:auth] == :bearer
    headers['Authorization'] = 'Bearer phoenix-a4-golden-unknown' if kase[:auth] == :unknown
    path = kase[:auth] == :query ? "#{kase[:path]}?api_key=#{user.api_key}" : kase[:path]
    if kase[:if_none_match] == :hit
      get path, headers: headers
      headers['If-None-Match'] = response.headers['ETag']
    end
    setup_sql = 'SELECT row_to_json(t)::text FROM users t ORDER BY id'
    setup = ActiveRecord::Base.connection.select_values(setup_sql).map { JSON.parse(_1) }

    send(kase[:method], path, headers: headers)

    { 'name' => kase[:name], 'expect' => kase[:expect].to_s, 'ignore' => kase[:ignore] || [],
      'env' => kase[:env], 'setup' => setup,
      'request' => { 'method' => kase[:method].to_s.upcase, 'target' => path, 'headers' => headers.to_a },
      'response' => { 'status' => response.status, 'body' => response.body,
                      'headers' => response.headers.to_h.transform_keys(&:downcase).except('date', 'content-length') } }
  end
end
