# frozen_string_literal: true

require 'rails_helper'
require_relative 'places_golden_support'

module ApiSharedGoldenOracle
  TABLES = %w[users trips tracks shared_links points tags places taggings].freeze
  AFTER = %w[shared_links].freeze
  OWNER = 951_001
  OTHER = 951_002
  KEY = 'phoenix-a4rest-shared-synthetic'
  LINK = 'a4951000-0000-4000-8000-000000000001'
  NOW = Time.utc(2026, 10, 3, 12)
  STAMP = '2026-03-28 12:00:00'
  T0 = Time.utc(2026, 3, 29).to_i
  SEQUENCES = { 'points_id_seq' => 959_000 }.freeze
  IMMICH = 'http://a4rest-immich.example.invalid'
  SECRET = 'phoenix-a4rest-cookie-synthetic-not-for-production'
  ACTIONS = %w[trip points route photos photos/public-0/thumbnail].freeze
  def self.setups = @setups ||= {}
end

require_relative 'api_shared_golden_cases'

RSpec.describe 'Phoenix fixture: golden shared API requests', type: :request do
  include ActiveSupport::Testing::TimeHelpers
  include PlacesGoldenSupport

  before do
    generator = ActiveSupport::CachingKeyGenerator.new(
      ActiveSupport::KeyGenerator.new(ApiSharedGoldenOracle::SECRET, iterations: 1000)
    )
    config = Rails.application.env_config.merge('action_dispatch.key_generator' => generator,
                                                'action_dispatch.show_exceptions' => :all,
                                                'action_dispatch.show_detailed_exceptions' => false)
    allow(Rails.application).to receive(:env_config).and_return(config)
  end

  it 'records shared responses and database effects from Rails' do
    oracle = ApiSharedGoldenOracle
    cases = places_cases(oracle).map do |entry|
      kase = { method: :get, auth: :none, expect: :own, env: {}, content: {},
               path: "/api/v1/shared/#{oracle::LINK}/#{entry[:action]}#{entry[:query]}" }.merge(entry)
      result = places_record(kase, oracle:, strict: true)
      shared_assert_response(result, entry)
      expect(result.fetch('after').fetch('shared_links')).to eq(
        oracle.setups.fetch(result.fetch('setup')).to_h.fetch('shared_links')
      )
      snapshot = oracle.setups.fetch(result.fetch('setup')).to_h
      expect(snapshot.fetch('users').first).to have_key('deleted_at')
      expect(snapshot.fetch('users').first.fetch('deleted_at')).to eq(entry.dig(:user, :deleted_at)&.tr(' ', 'T'))
      expect(result.fetch('ignore')).to eq([])
      expect(result).not_to have_key('mask')
      if entry[:cookie]
        result['request']['headers'].reject! { |name, _value| name == 'Cookie' }
        result['runtime_cookie'] = entry[:cookie].to_s
      end
      result['session_cookie'] = shared_session_cookie
      expect(result['session_cookie']).not_to be_nil if result.dig('response', 'headers').key?('set-cookie')
      expect(WebMock).not_to have_requested(:any, /a4rest-immich/) if entry[:no_fetch]
      result
    end
    path = Rails.root.join(ENV.fetch('API_GOLDEN_OUTPUT', 'app-phoenix/test/fixtures/api_shared/golden.json'))
    FileUtils.mkdir_p(path.dirname)
    fixture = { 'time_zone' => ENV.fetch('TIME_ZONE', nil), 'now' => oracle::NOW.iso8601,
                'sequences' => oracle::SEQUENCES, 'setups' => oracle.setups.sort.to_h,
                'cases' => cases.sort_by { _1['name'] } }
    File.write(path, "#{Oj.dump(fixture, mode: :strict, indent: 2, float_precision: 0).rstrip}\n")
  end

  def places_seed(kase)
    oracle = ApiSharedGoldenOracle
    reset!
    allow(DawarichSettings).to receive(:self_hosted?).and_return(true)
    Rails.cache.clear
    WebMock.reset!
    places_sql("TRUNCATE #{oracle::TABLES.join(',')} CASCADE")
    stamps = { created_at: oracle::STAMP, updated_at: oracle::STAMP }
    user = { status: 1, timezone: 'UTC', distance_unit: 'km' }.merge(kase[:user] || {})
    settings = { 'timezone' => user[:timezone], 'maps' => { 'distance_unit' => user[:distance_unit] } }
    if kase[:seed] == :provider
      settings.merge!('immich_url' => oracle::IMMICH, 'immich_api_key' => 'a4rest-immich-synthetic')
    end
    places_insert('users', id: oracle::OWNER, email: 'a4rest-shared@example.invalid', api_key: oracle::KEY,
                           status: user[:status], settings:, visits_redetected_at: oracle::STAMP, **stamps)
    places_insert('users', id: oracle::OTHER, email: 'a4rest-other@example.invalid', api_key: 'a4rest-other-synthetic',
                           status: 1, settings: { 'timezone' => 'UTC' }, visits_redetected_at: oracle::STAMP, **stamps)
    trip = { id: 951_101, user_id: oracle::OWNER, name: 'Synthetic shared trip', distance: 123_456,
             started_at: Time.at(oracle::T0).utc, ended_at: Time.at(oracle::T0 + 3600).utc, **stamps }
    trip.merge!(ended_at: Time.at(oracle::T0 + 20_000).utc) if %i[many private_many].include?(kase[:seed])
    places_insert('trips', trip.merge(kase[:trip] || {}))
    places_insert('trips', trip.merge(id: 951_102, user_id: oracle::OTHER))
    [oracle::OWNER, oracle::OTHER].each_with_index do |owner, index|
      places_insert('tracks', id: 951_201 + index, user_id: owner,
                             start_at: Time.at(oracle::T0).utc, end_at: Time.at(oracle::T0 + 3600).utc,
                             original_path: 'SRID=4326;LINESTRING(13 52,13.1 52.1)', **stamps)
    end
    link_row = { id: oracle::LINK, user_id: oracle::OWNER, name: 'Synthetic share', resource_type: 0,
                 resource_id: 951_101, settings: {}, **stamps }
    places_insert('shared_links', link_row.merge(kase[:link] || {}))
    places_sql('DELETE FROM shared_links') if kase[:missing]
    shared_seed_points(kase, stamps)
    places_sql("UPDATE points SET lonlat=NULL WHERE id=#{kase[:null_id]}") if kase[:null_id]
    shared_seed_provider(kase) if kase[:seed] == :provider
    zones = Users::PrivacyZones.new(User.find(oracle::OWNER)).call
    fingerprint = Digest::MD5.hexdigest(zones.sort_by { |zone| zone.values_at(:lat, :lon, :radius) }.to_s)
    @acl_key = "shared_link/#{oracle::LINK}/photo_ids/v2/#{fingerprint}"
    kase[:cache_keys] = [@acl_key]
    link = SharedLink.find_by(id: oracle::LINK)
    places_sql("UPDATE users SET deleted_at='#{user[:deleted_at]}' WHERE id=#{oracle::OWNER}") if user[:deleted_at]
    resource = link&.resource unless user[:deleted_at]
    range = case link&.resource_type
            when 'trip' then resource && [resource.started_at.iso8601, resource.ended_at.iso8601]
            when 'track' then resource && [resource.start_at.iso8601, resource.end_at.iso8601]
            end
    kase[:cache_keys] << "photos_search/#{oracle::OWNER}/#{range.join('/')}" if range
  end

  def places_headers(kase, body, oracle:)
    headers = super
    return headers unless kase[:cookie]

    link = SharedLink.find(oracle::LINK)
    token = kase[:cookie] == :old ? Digest::SHA256.hexdigest("#{link.id}:synthetic-phrase") : link.unlock_token
    jar = ActionDispatch::Request.new(Rails.application.env_config.dup).cookie_jar
    name = "shared_link_#{link.id}"
    jar.encrypted[name] = { value: token, expires: oracle::NOW + 3600 }
    headers.merge('Cookie' => "#{name}=#{ERB::Util.url_encode(jar[name])}")
  end

  def shared_seed_points(kase, stamps)
    oracle = ApiSharedGoldenOracle
    case kase[:seed]
    when :empty then nil
    when :many, :private_many
      count = kase.fetch(:count)
      places_sql(<<~SQL.squish)
        INSERT INTO points (id,user_id,timestamp,lonlat,anomaly,created_at,updated_at)
        SELECT 951401+i,#{oracle::OWNER},#{oracle::T0}+i,
          ST_SetSRID(ST_MakePoint(13.405000000000001,52.520000000000003),4326),false,
          '#{oracle::STAMP}','#{oracle::STAMP}' FROM generate_series(0,#{count - 1}) i
      SQL
      if kase[:seed] == :private_many
        shared_privacy_zone(stamps)
        places_sql('UPDATE points SET lonlat=ST_SetSRID(ST_MakePoint(13,52),4326) WHERE id=951401')
      end
    when :timeline
      [-3601, -3600, 79_199, 79_200].each_with_index do |offset, i|
        shared_point(951_401 + i, oracle::T0 + offset, stamps)
      end
    when :live, :live_private
      shared_point(951_401, oracle::NOW.to_i - kase.fetch(:age) - 1, stamps)
      shared_point(951_402, oracle::NOW.to_i - kase.fetch(:age), stamps,
                   lonlat: kase[:seed] == :live_private ? 'SRID=4326;POINT(13 52)' : 'SRID=4326;POINT(13.4 52.5)')
      shared_point(951_403, oracle::NOW.to_i, stamps, anomaly: true)
      shared_privacy_zone(stamps) if kase[:seed] == :live_private
    when :route
      [-1, 0, 1].each_with_index do |offset, i|
        shared_point(951_401 + i, Time.parse("#{oracle::STAMP} UTC").to_i + offset, stamps)
      end
      shared_point(951_404, Time.parse("#{oracle::STAMP} UTC").to_i + 2, stamps, anomaly: true)
    else
      [-1, 0, 3600, 3601].each_with_index do |offset, i|
        shared_point(951_401 + i, oracle::T0 + offset, stamps,
                     track_id: [-1, 3601].include?(offset) ? 951_201 : nil)
      end
      shared_point(951_405, oracle::T0 + 10, stamps, anomaly: true)
      shared_point(951_406, oracle::T0 + 20, stamps, user_id: oracle::OTHER, track_id: 951_202)
      if %i[privacy provider boundary].include?(kase[:seed])
        shared_privacy_zone(stamps)
        shared_point(951_407, oracle::T0 + 30, stamps, lonlat: 'SRID=4326;POINT(13 52)')
      end
      if kase[:seed] == :boundary
        [99, 100, 101].each_with_index do |distance, i|
          shared_point(951_408 + i, oracle::T0 + 31 + i, stamps)
          places_sql(<<~SQL.squish)
            UPDATE points SET lonlat=ST_Project(ST_SetSRID(ST_MakePoint(13,52),4326)::geography,
              #{distance},radians(90)) WHERE id=#{951_408 + i}
          SQL
        end
      end
    end
  end

  def shared_point(id, timestamp, stamps, **extra)
    places_insert('points', { id:, user_id: ApiSharedGoldenOracle::OWNER, timestamp:,
                             lonlat: 'SRID=4326;POINT(13.405000000000001 52.520000000000003)',
                             anomaly: false, **stamps }.merge(extra))
  end

  def shared_privacy_zone(stamps)
    places_insert('places', id: 951_501, user_id: ApiSharedGoldenOracle::OWNER, name: 'Synthetic private place',
                           latitude: 52, longitude: 13, lonlat: 'SRID=4326;POINT(14 53)', source: 0, **stamps)
    places_insert('tags', id: 951_601, user_id: ApiSharedGoldenOracle::OWNER, name: 'Synthetic privacy',
                         privacy_radius_meters: 100, **stamps)
    places_insert('taggings', id: 951_701, taggable_type: 'Place', taggable_id: 951_501, tag_id: 951_601, **stamps)
  end

  def shared_seed_provider(kase)
    oracle = ApiSharedGoldenOracle
    photos = (0..100).map do |i|
      { id: "public-#{i}", type: 'IMAGE', fileCreatedAt: Time.at(oracle::T0 + 1800).utc.iso8601,
        exifInfo: { latitude: 52.5, longitude: 13.4 } }
    end
    photos.prepend(photos.first.merge(id: 'unlocated', exifInfo: {}),
                   photos.first.merge(id: 'private', exifInfo: { latitude: 52, longitude: 13 }))
    stub_request(:post, "#{oracle::IMMICH}/api/search/metadata")
      .with { |request| JSON.parse(request.body)['page'] == 1 }
      .to_return(status: 200, headers: { 'Content-Type' => 'application/json' },
                 body: JSON.generate(assets: { items: photos }))
    stub_request(:post, "#{oracle::IMMICH}/api/search/metadata")
      .with { |request| JSON.parse(request.body)['page'] == 2 }
      .to_return(status: 200, headers: { 'Content-Type' => 'application/json' },
                 body: JSON.generate(assets: { items: [] }))
    stub_request(:get, "#{oracle::IMMICH}/api/assets/public-100/thumbnail?size=preview")
      .to_return(status: kase.fetch(:upstream_status, 200), headers: { 'Content-Type' => 'image/jpeg' },
                 body: "\xFF\xD8synthetic-jpeg\xFF\xD9".b)
  end

  def shared_assert_response(result, entry)
    recorded = result.fetch('response')
    expect(recorded.fetch('status')).to eq(entry.fetch(:status, 200)), entry[:name]
    expect(recorded.fetch('headers').keys.grep(/\Ax-dawarich-/)).to eq([])
    expect(recorded.fetch('headers')['cache-control']).to eq(entry[:cache]) if entry[:cache]
    body = recorded['body']
    payload = JSON.parse(body) if body.present? && !entry[:jpeg]
    expect(payload).to eq(entry[:json]) if entry.key?(:json)
    expect(payload).to include([0.0, 0.0, entry[:null_ts]]) if entry[:null_ts]
    expect(payload.size).to eq(entry[:size]), entry[:name] if entry[:size]
    expect(payload.map(&:last)).to eq(entry[:timestamps]), entry[:name] if entry[:timestamps]
    expect(payload['distance']).to eq(entry[:distance]) if entry[:distance]
    expect(payload).not_to have_key('distance') if entry[:no_distance]
    expect(payload).not_to include('email', 'api_key', 'user_id', 'settings') if payload.is_a?(Hash)
    expect(recorded['body_base64']).to eq(Base64.strict_encode64("\xFF\xD8synthetic-jpeg\xFF\xD9".b)) if entry[:jpeg]
    return unless entry.key?(:acl) || entry[:acl_size]

    cache = result.fetch('cache_after').fetch(@acl_key)
    expect(cache.fetch('ttl')).to eq(600)
    expect(cache.fetch('value').keys).to eq(entry[:acl]) if entry.key?(:acl)
    expect(cache.fetch('value').size).to eq(entry[:acl_size]) if entry[:acl_size]
  end

  def shared_session_cookie
    headers = response.headers.to_h.transform_keys(&:downcase)
    line = Array(headers['set-cookie']).find { _1.start_with?('_dawarich_session=') }
    return nil unless line

    cookie, *attributes = line.split(';').map(&:strip)
    jar = ActionDispatch::Request.new(Rails.application.env_config.merge('HTTP_COOKIE' => cookie)).cookie_jar
    { 'keys' => jar.encrypted['_dawarich_session'].keys.sort, 'attributes' => attributes.sort }
  end
end
