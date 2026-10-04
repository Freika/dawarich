# frozen_string_literal: true

require 'rails_helper'
require_relative 'places_golden_support'

module ApiVisitsGoldenOracle
  TABLES = %w[users areas places visits points place_visits notes tags taggings instance_settings].freeze
  AFTER = TABLES.drop(1).freeze
  OWNER = 953_001
  OTHER = 953_002
  KEY = 'phoenix-a4rest-visits-synthetic'
  NOW = Time.utc(2026, 10, 3, 12)
  STAMP = '2026-09-01 12:00:00.123456'
  SEQUENCES = { 'visits_id_seq' => 959_100, 'places_id_seq' => 959_200 }.freeze
  P = '/api/v1/visits'
  H = "#{P}/953301".freeze
  JSON_TYPE = { 'Content-Type' => 'application/json' }.freeze

  def self.setups = @setups ||= {}
end

require_relative 'api_visits_golden_cases'

RSpec.describe 'Phoenix fixture: golden visits API requests', type: :request do
  include ActiveSupport::Testing::TimeHelpers
  include PlacesGoldenSupport

  it 'records visits responses and database effects from Rails' do
    oracle = ApiVisitsGoldenOracle
    cases = places_cases(oracle).map do |entry|
      kase = { method: :get, auth: :bearer, expect: :own, env: {}, content: oracle::JSON_TYPE }.merge(entry)
      kase[:env]['STORE_GEODATA'] = kase[:store_geodata].to_s if kase.key?(:store_geodata)
      result = places_record(kase, oracle:, strict: true)
      status = result.dig('response', 'status')
      expect(status).to eq(entry.fetch(:status, 200)), "#{entry[:name]}: HTTP#{status}"
      if entry[:tombstone]
        row = result.fetch('after').fetch('visits').find { _1['id'] == 953_301 }
        expect(row).not_to be_nil
        expect(row.fetch('deleted_at')).to eq('2026-10-03T12:00:00')
      end
      before = oracle.setups.fetch(result.fetch('setup')).to_h
      after = result.fetch('after')
      body = result.dig('response', 'body')
      json = result.dig('response', 'headers', 'content-type').to_s.start_with?('application/json')
      payload = body.present? && json ? JSON.parse(body) : nil
      expect(payload.slice(*entry[:fields].keys)).to eq(entry[:fields]), entry[:name] if entry[:fields]
      expect(payload.map { _1['id'] }).to eq(entry[:ids]), entry[:name] if entry[:ids]
      expect(payload.length).to eq(entry[:count]), entry[:name] if entry[:count]
      headers = result.dig('response', 'headers')
      expect(headers.slice(*entry[:headers].keys)).to eq(entry[:headers]) if entry[:headers]
      result['jobs_after'] = enqueued_jobs.map { { 'job' => _1[:job].name, 'args' => _1[:args] } }
      expect(result['jobs_after'].length).to eq(entry[:jobs]), entry[:name] if entry[:jobs]
      if kase[:method] == :get || entry.fetch(:status, 200) >= 400
        expect(after).to eq(before.slice(*oracle::AFTER)), entry[:name]
        expect(result['jobs_after']).to eq([])
      end
      if entry[:tombstone]
        expect(after.fetch('points')).to eq(before.fetch('points'))
        expect(after.fetch('place_visits')).to eq(before.fetch('place_visits'))
        expect(after.fetch('notes')).to eq(before.fetch('notes'))
      end
      if entry[:created]
        expect(after.fetch('visits').length).to eq(before.fetch('visits').length + 1)
        expect(payload['id']).to eq(959_100)
      end
      expect(after.fetch('places').length).to eq(before.fetch('places').length + 1) if entry[:new_place]
      if entry[:revived]
        row = after.fetch('visits').find { _1['id'] == 953_301 }
        expect(row.values_at('deleted_at', 'status')).to eq([nil, 1])
      end
      if entry[:merged]
        expect(after.fetch('visits').map { _1['id'] }).not_to include(953_302)
        expect(after.fetch('points').map { _1['visit_id'] }).to eq([953_301, 953_301])
        expect(after.fetch('notes')).to eq([])
        expect(after.fetch('place_visits').map { _1['visit_id'] }).to eq([953_301])
      end
      if entry[:dropped_fields]
        place = after.fetch('places').find { _1['id'] == payload['id'] }
        expect(place.values_at('city', 'country')).to eq([nil, nil])
      end
      if entry[:selected]
        row = after.fetch('visits').find { _1['id'] == 953_301 }
        expect(row.values_at('name', 'status')).to eq([payload['name'], 1])
        expect(row['place_id']).to eq(payload['id'])
        expect(payload['id']).to eq(953_202) if entry[:dedup]
      end
      if entry[:place_fields]
        place = after.fetch('places').find { _1['id'] == payload['id'] }
        expect(place.slice(*entry[:place_fields].keys)).to eq(entry[:place_fields])
      end
      if entry[:adopted]
        expect(after.fetch('places').find { _1['id'] == 953_202 }['demo']).to be(false)
        expect(after.fetch('tags').first['demo']).to be(false)
      end
      if entry[:months]
        values = result.fetch('cache_after').values.map { _1['value'] }
        expect(values).to eq(entry[:months] == :berlin ? ['primed', nil, 'primed'] : [nil, nil, 'primed'])
      end
      expect(result.fetch('ignore')).to eq([])
      expect(result).not_to have_key('mask')
      result
    end
    path = Rails.root.join(ENV.fetch('API_GOLDEN_OUTPUT', 'app-phoenix/test/fixtures/api_visits/golden.json'))
    FileUtils.mkdir_p(path.dirname)
    fixture = { 'time_zone' => ENV.fetch('TIME_ZONE', nil), 'now' => oracle::NOW.iso8601,
                'sequences' => oracle::SEQUENCES, 'setups' => oracle.setups.sort.to_h,
                'cases' => cases.sort_by { _1['name'] } }
    File.write(path, "#{Oj.dump(fixture, mode: :strict, indent: 2, float_precision: 0).rstrip}\n")
  end

  def places_seed(kase)
    oracle = ApiVisitsGoldenOracle
    reset!
    clear_enqueued_jobs
    Rails.cache.clear
    allow(DawarichSettings).to receive(:self_hosted?).and_return(true)
    allow(DawarichSettings).to receive(:store_geodata?).and_return(kase.fetch(:store_geodata, true))
    places_sql("TRUNCATE #{oracle::TABLES.join(',')} CASCADE")
    InstanceSettings::Resolver.reset!
    stamps = { created_at: oracle::STAMP, updated_at: oracle::STAMP }
    user = { status: 1, timezone: 'UTC' }.merge(kase[:user] || {})
    places_insert('users', id: oracle::OWNER, email: 'a4rest-visits@example.invalid', api_key: oracle::KEY,
                           status: user[:status], settings: { 'timezone' => user[:timezone] },
                           visits_redetected_at: oracle::STAMP, **stamps)
    places_insert('users', id: oracle::OTHER, email: 'a4rest-other@example.invalid', api_key: 'a4rest-visits-other',
                           status: 1, settings: { 'timezone' => 'UTC' }, visits_redetected_at: oracle::STAMP, **stamps)
    [oracle::OWNER, oracle::OTHER].each_with_index do |owner, i|
      places_insert('areas', id: 953_101 + i, user_id: owner, name: 'Synthetic area',
                            latitude: 53, longitude: 14, radius: 100, **stamps)
    end
    [oracle::OWNER, oracle::OWNER, oracle::OTHER, oracle::OWNER].each_with_index do |owner, i|
      lat, lon = i == 3 ? [53, 14] : [52.52, 13.405]
      places_insert('places', id: 953_201 + i, user_id: owner, name: "Place #{i + 1}", source: 1,
                             latitude: lat, longitude: lon, lonlat: "SRID=4326;POINT(#{lon} #{lat})",
                             demo: %i[demo adopt].include?(kase[:seed]),
                             geodata: { properties: { osm_id: 42 } }, **stamps)
    end
    [39, 40, 69, 70, nil, nil, nil, nil, nil, nil].each_with_index do |confidence, i|
      day = [1, 2, 3, 4, 2, 2, 5, 5, 2, 4][i]
      status = i == 1 ? 0 : 1
      status = 2 if i == 5 || (i.zero? && kase[:seed] == :declined)
      place_id = [953_201, 953_201, 953_204, 953_204, nil, nil, nil, nil, 953_201, nil][i]
      places_insert('visits', id: 953_301 + i, user_id: i == 8 ? oracle::OTHER : oracle::OWNER,
                             place_id:,
                             name: "Visit #{i + 1}", status:, confidence:, duration: 60,
                             deleted_at: i == 4 || (i.zero? && kase[:seed] == :deleted) ? oracle::STAMP : nil,
                             started_at: "2026-09-0#{day} 12:00:00",
                             ended_at: "2026-09-0#{day} #{i == 3 ? '23' : '13'}:00:00",
                             demo: kase[:seed] == :demo, **stamps)
    end
    [953_301, 953_302].each_with_index do |visit, i|
      places_insert('points', id: 953_401 + i, user_id: oracle::OWNER, visit_id: visit,
                             timestamp: Time.utc(2026, 9, 1 + i, 12, 30).to_i,
                             lonlat: 'SRID=4326;POINT(13.405 52.52)', **stamps)
      places_insert('place_visits', id: 953_501 + i, place_id: 953_203, visit_id: visit, **stamps)
    end
    places_insert('notes', id: 953_601, user_id: oracle::OWNER, body: 'Synthetic merge note',
                           attachable_type: 'Visit', attachable_id: 953_302, noted_at: oracle::STAMP, **stamps)
    places_insert('tags', id: 953_701, user_id: oracle::OWNER, name: 'Synthetic tag',
                          icon: 'x', color: '#123456', demo: %i[demo adopt].include?(kase[:seed]), **stamps)
    [953_201, 953_202].each_with_index do |place, i|
      places_insert('taggings', id: 953_801 + i, tag_id: 953_701, taggable_type: 'Place',
                               taggable_id: place, **stamps)
    end
    if kase[:seed] == :area_inside
      places_sql('UPDATE areas SET latitude=52.6,longitude=13.5 WHERE id=953101')
      places_sql('UPDATE visits SET area_id=953101 WHERE id=953310')
    end
    owner = User.find(oracle::OWNER)
    kase[:cache_keys] = %w[2026-08 2026-09 2026-10].map do |month|
      key = Timeline::MonthSummary.cache_key_for(owner, month).join('/')
      Rails.cache.write(key, 'primed', expires_in: 300)
      key
    end
    visits_provider(kase, owner) if kase[:provider]
    clear_enqueued_jobs
  end

  def visits_provider(kase, owner)
    places_insert('instance_settings', id: 953_901, key: 'photon_api_host',
                                       value: JSON.generate('photon.test.example.com'),
                                       created_at: ApiVisitsGoldenOracle::STAMP, updated_at: ApiVisitsGoldenOracle::STAMP)
    InstanceSettings::Resolver.reset!
    results = [42, 43].map do |id|
      data = { 'properties' => { 'osm_id' => id, 'osm_type' => 'N', 'name' => "Synthetic #{id}" },
               'geometry' => { 'coordinates' => [13.405, 52.52] } }
      double(data:, latitude: 52.52, longitude: 13.405)
    end
    allow(Geocoder).to receive(:search).and_return(results)
    search = Places::NearbySearch.new(user: owner, latitude: 52.52, longitude: 13.405, cache: true)
    kase[:cache_keys] << search.send(:cache_key)
  end
end
