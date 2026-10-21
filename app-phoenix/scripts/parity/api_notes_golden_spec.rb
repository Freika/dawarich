# frozen_string_literal: true

require 'rails_helper'
require_relative 'places_golden_support'

module ApiNotesGoldenOracle
  TABLES = %w[users trips areas visits places notes action_text_rich_texts].freeze
  AFTER = %w[notes action_text_rich_texts].freeze
  OWNER = 952_001
  OTHER = 952_002
  KEY = 'phoenix-a4rest-notes-synthetic'
  NOW = Time.utc(2026, 10, 3, 12)
  STAMP = '2026-09-01 12:00:00.123456'
  SEQUENCES = { 'notes_id_seq' => 959_000 }.freeze
  P = '/api/v1/notes'
  H = "#{P}/952201".freeze
  JSON_TYPE = { 'Content-Type' => 'application/json' }.freeze
  CREATE = { body: 'Created body', noted_at: '2026-09-02T12:00:00Z' }.freeze
  COMBINED = "e#{[0x301].pack('U')}".freeze
  CASES = [
    { name: 'destroy', method: :delete, path: H, status: 200,
      json: { 'message' => 'Note was successfully deleted' }, deleted: 952_201 },
    { name: 'index_order', path: P, ids: [952_202, 952_201, 952_207, 952_206, 952_205, 952_203] },
    { name: 'index_empty', path: P, seed: :empty, json: [] },
    { name: 'index_standalone', path: "#{P}?standalone=true", ids: [952_202, 952_201] },
    { name: 'index_standalone_false', path: "#{P}?standalone=false",
      ids: [952_202, 952_201, 952_207, 952_206, 952_205, 952_203] },
    { name: 'index_type', path: "#{P}?attachable_type=Trip", ids: [952_203] },
    { name: 'index_id', path: "#{P}?attachable_id=952131", ids: [952_207] },
    { name: 'index_type_and_id', path: "#{P}?attachable_type=Trip&attachable_id=952131", json: [] },
    { name: 'show', path: H, fields: { 'title' => 'Synthetic note', 'body' => 'Original body',
      'latitude' => 52.52, 'longitude' => 13.405, 'attachable_type' => nil, 'date' => '2026-09-01' } },
    { name: 'show_berlin_utc_date', path: H, user: { timezone: 'Europe/Berlin' },
      fields: { 'date' => '2026-09-01', 'noted_at' => '2026-09-02T00:30:00.000+02:00' } },
    { name: 'show_nil_coordinates', path: "#{P}/952202", fields: { 'latitude' => nil, 'longitude' => nil } },
    { name: 'show_conditional', path: H, conditional: true, status: 304 },
    { name: 'show_english', path: H, headers: { 'Accept-Language' => 'de' } },
    { name: 'create', method: :post, path: P, body: { note: CREATE }, status: 201, created: true,
      fields: { 'id' => 959_000, 'body' => 'Created body', 'created_at' => '2026-10-03T12:00:00.000Z' } },
    { name: 'create_body_10000', method: :post, path: P,
      body: { note: CREATE.merge(body: 'a' * 10_000) }, status: 201, created: true, length: 10_000 },
    { name: 'create_body_10001', method: :post, path: P,
      body: { note: CREATE.merge(body: 'a' * 10_001) }, status: 422, error: 'Body is too long' },
    { name: 'create_multibyte_10000', method: :post, path: P,
      body: { note: CREATE.merge(body: 'é' * 10_000) }, status: 201, created: true, length: 10_000 },
    { name: 'create_multibyte_10001', method: :post, path: P,
      body: { note: CREATE.merge(body: 'é' * 10_001) }, status: 422, error: 'Body is too long' },
    { name: 'create_combining_10000', method: :post, path: P,
      body: { note: CREATE.merge(body: COMBINED * 5000) }, status: 201, created: true, length: 10_000 },
    { name: 'create_combining_10001', method: :post, path: P,
      body: { note: CREATE.merge(body: "#{COMBINED * 5000}e") }, status: 422, error: 'Body is too long' },
    { name: 'create_blank_body', method: :post, path: P, body: { note: CREATE.merge(body: ' ') },
      status: 422, error: "Body can't be blank" },
    { name: 'create_missing_date', method: :post, path: P, body: { note: CREATE.except(:noted_at) },
      status: 422, error: "Noted at can't be blank" },
    { name: 'create_null_coordinates', method: :post, path: P,
      body: { note: CREATE.merge(latitude: nil, longitude: nil) }, status: 201, created: true,
      fields: { 'latitude' => nil, 'longitude' => nil } },
    { name: 'create_one_coordinate', method: :post, path: P,
      body: { note: CREATE.merge(latitude: 0) }, status: 201, created: true,
      fields: { 'latitude' => nil, 'longitude' => nil } },
    { name: 'create_zero_coordinates', method: :post, path: P,
      body: { note: CREATE.merge(latitude: 0, longitude: 0) }, status: 201, created: true,
      fields: { 'latitude' => 0.0, 'longitude' => 0.0 } },
    { name: 'create_berlin', method: :post, path: P, user: { timezone: 'Europe/Berlin' },
      body: { note: CREATE.merge(noted_at: '2026-09-01T23:30:00Z') }, status: 201, created: true,
      fields: { 'date' => '2026-09-01', 'noted_at' => '2026-09-02T01:30:00.000+02:00' } },
    { name: 'create_extra_keys', method: :post, path: P,
      body: { note: CREATE.merge(user_id: OTHER, source_digest: 'ignored', lonlat: 'POINT(1 2)'), extra: 'ignored' },
      status: 201, created: true },
    { name: 'create_missing_root', method: :post, path: P, body: CREATE, expect: :rails, status: 201, created: true },
    { name: 'create_empty_root', method: :post, path: P, body: { note: {} }, expect: :rails, status: 400 },
    { name: 'create_duplicate_date', method: :post, path: P,
      body: { note: CREATE.merge(attachable_type: 'Trip', attachable_id: 952_101, noted_at: '2026-09-01T13:00:00Z') },
      status: 422, error: 'Date has already been taken' },
    { name: 'create_foreign_collision', method: :post, path: P, seed: :foreign_collision,
      body: { note: CREATE.merge(attachable_type: 'Trip', attachable_id: 952_101) }, status: 422,
      error: 'Date has already been taken' },
    { name: 'create_trip_out_of_range', method: :post, path: P,
      body: { note: CREATE.merge(attachable_type: 'Trip', attachable_id: 952_101, noted_at: '2026-09-04T12:00:00Z') },
      status: 422, error: 'Date must be within' },
    { name: 'create_invalid_attachable_type', method: :post, path: P,
      body: { note: CREATE.merge(attachable_type: 'User', attachable_id: OWNER) }, status: 422,
      error: 'Attachable type is not included' },
    { name: 'update_source_digest', method: :patch, path: H,
      body: { note: { body: 'Edited body', source_digest: 'ignored' } }, digest: true,
      fields: { 'body' => 'Edited body' } },
    { name: 'update_one_coordinate', method: :patch, path: H, body: { note: { latitude: 0 } },
      fields: { 'latitude' => 52.52, 'longitude' => 13.405 } },
    { name: 'update_two_zero_coordinates', method: :patch, path: H, body: { note: { latitude: 0, longitude: 0 } },
      fields: { 'latitude' => 0.0, 'longitude' => 0.0 } },
    { name: 'update_put', method: :put, path: H, body: { note: { title: 'Put title' } },
      fields: { 'title' => 'Put title' } },
    { name: 'update_self_exclusion', method: :patch, path: "#{P}/952203", body: { note: { body: 'Self update' } } },
    { name: 'update_duplicate_date', method: :patch, path: H,
      body: { note: { attachable_type: 'Trip', attachable_id: 952_101, noted_at: '2026-09-01T13:00:00Z' } },
      status: 422, error: 'Date has already been taken' },
    { name: 'update_null_date', method: :patch, path: H, body: { note: { noted_at: nil } }, status: 422,
      error: "Noted at can't be blank" },
    { name: 'auth_none', path: H, auth: :none, status: 401 },
    { name: 'auth_unknown', path: H, auth: :unknown, status: 401 },
    { name: 'auth_pending', path: H, user: { status: 3 }, status: 402, fields: { 'error' => 'payment_required' } },
    { name: 'auth_inactive', path: H, user: { status: 0 } },
    { name: 'auth_query', path: H, auth: :query },
    { name: 'replay_head', path: H, method: :head, expect: :rails },
    { name: 'replay_suffix', path: "#{H}.json", expect: :rails },
    { name: 'replay_format_xml', path: "#{H}?format=xml", expect: :rails },
    { name: 'replay_kill_switch', path: H, env: { 'DAWARICH_RAILS_SLICES' => 'api_notes' }, expect: :rails },
    { name: 'replay_query_shape', path: "#{H}?unused[]=x", expect: :rails },
    { name: 'replay_cloud', path: H, env: { 'SELF_HOSTED' => 'false' }, expect: :rails }
  ].concat(%w[Trip Area Visit Place].flat_map.with_index do |type, i|
    parent = [952_101, 952_111, 952_121, 952_131][i]
    [{ name: "create_#{type.downcase}", method: :post, path: P,
       body: { note: CREATE.merge(attachable_type: type, attachable_id: parent) }, status: 201, created: true },
     { name: "create_foreign_#{type.downcase}", method: :post, path: P,
       body: { note: CREATE.merge(attachable_type: type, attachable_id: parent + 1) }, status: 422,
       error: 'Attachable must belong to the same user' },
     { name: "create_missing_#{type.downcase}", method: :post, path: P,
       body: { note: CREATE.merge(attachable_type: type, attachable_id: 959_999) }, status: 422,
       error: "Attachable can't be blank" }]
  end).concat(%i[get patch delete].flat_map do |method|
    [952_204, 959_999].map do |id|
      { name: "#{method}_missing_or_foreign_#{id}", method:, path: "#{P}/#{id}", status: 404,
        **(method == :patch ? { body: { note: { body: 'No write' } } } : {}),
        json: { 'error' => 'Record not found' } }
    end
  end).freeze

  def self.setups = @setups ||= {}
end

RSpec.describe 'Phoenix fixture: golden notes API requests', type: :request do
  include ActiveSupport::Testing::TimeHelpers
  include PlacesGoldenSupport

  before do
    config = Rails.application.env_config.merge('action_dispatch.show_detailed_exceptions' => false)
    allow(Rails.application).to receive(:env_config).and_return(config)
  end

  it 'records notes responses and database effects from Rails' do
    notes_golden_fixture
  end

  it 'compares notes fixtures without writing in read-back mode' do
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with('WRITE_PHOENIX_FIXTURES').and_return(nil)
    path = Rails.root.join(ENV.fetch('API_GOLDEN_OUTPUT', 'app-phoenix/test/fixtures/api_notes/golden.json'))
    expect(File).not_to receive(:write).with(path, anything)
    expect(FileUtils).not_to receive(:mkdir_p).with(path.dirname)

    notes_golden_fixture
  end

  it 'records the closure corpus with exactly one terminal newline', :closure_single_newline do
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with('WRITE_PHOENIX_FIXTURES').and_return('1')

    notes_golden_fixture

    bytes = Rails.root.join('app-phoenix/test/fixtures/a12f2a/closure.json').binread
    expect(bytes).to match(/[^\n]\n\z/)
  end

  it 'records a stable bad-request response for an empty note root' do
    oracle = ApiNotesGoldenOracle
    entry = oracle::CASES.find { _1[:name] == 'create_empty_root' }
    kase = { auth: :bearer, env: {}, content: oracle::JSON_TYPE }.merge(entry)
    result = places_record(kase, oracle:, strict: true)

    expect(result.dig('response', 'status')).to eq(400)
    expect(result.dig('response', 'body') == JSON.generate(status: 400, error: 'Bad Request')).to be(true)
  end

  def notes_golden_fixture
    oracle = ApiNotesGoldenOracle
    oracle.setups.clear
    cases = places_cases(oracle).map do |entry|
      kase = { method: :get, auth: :bearer, expect: :own, env: {}, content: oracle::JSON_TYPE }.merge(entry)
      result = places_record(kase, oracle:, strict: true)
      expect(result.dig('response', 'status')).to eq(entry.fetch(:status, 200)), entry[:name]
      body = result.dig('response', 'body')
      json = result.dig('response', 'headers', 'content-type').to_s.start_with?('application/json')
      payload = body.present? && json ? JSON.parse(body) : nil
      expect(payload).to eq(entry[:json]) if entry[:json]
      expect(payload.slice(*entry[:fields].keys)).to eq(entry[:fields]), entry[:name] if entry[:fields]
      expect(payload.map { _1.fetch('id') }).to eq(entry[:ids]) if entry[:ids]
      expect(payload.fetch('body').length).to eq(entry[:length]) if entry[:length]
      expect(payload.fetch('errors').any? { _1.start_with?(entry[:error]) }).to be(true), entry[:name] if entry[:error]
      before = oracle.setups.fetch(result.fetch('setup')).to_h
      after = result.fetch('after')
      expect(after.fetch('action_text_rich_texts')).to eq(before.fetch('action_text_rich_texts'))
      if kase[:method] == :get || entry.fetch(:status, 200) >= 400
        expect(after.fetch('notes')).to eq(before.fetch('notes'))
      end
      if entry[:created]
        created = after.fetch('notes').find { _1.fetch('id') == 959_000 }
        expect(created.fetch('user_id')).to eq(oracle::OWNER)
        expect(created.fetch('source_digest')).to be_nil
        expect(after.fetch('notes').size).to eq(before.fetch('notes').size + 1)
        expect(result.dig('response', 'headers')).to have_key('etag')
      end
      if entry[:digest]
        expect(after.fetch('notes').find { _1.fetch('id') == 952_201 }.fetch('source_digest')).to eq(
          before.fetch('notes').find { _1.fetch('id') == 952_201 }.fetch('source_digest')
        )
      end
      expect(after.fetch('notes').map { _1.fetch('id') }).not_to include(entry[:deleted]) if entry[:deleted]
      expect(result.fetch('ignore')).to eq([])
      expect(result).not_to have_key('mask')
      result
    end
    path = Rails.root.join(ENV.fetch('API_GOLDEN_OUTPUT', 'app-phoenix/test/fixtures/api_notes/golden.json'))
    fixture = { 'time_zone' => ENV.fetch('TIME_ZONE', nil), 'now' => oracle::NOW.iso8601,
                'sequences' => oracle::SEQUENCES, 'setups' => oracle.setups.sort.to_h,
                'cases' => cases.sort_by { _1['name'] } }
    encoded = "#{Oj.dump(fixture, mode: :strict, indent: 2, float_precision: 0).rstrip}\n"
    if ENV['WRITE_PHOENIX_FIXTURES'] == '1'
      FileUtils.mkdir_p(path.dirname)
      File.write(path, encoded)
    else
      expect(path.read == encoded).to be(true), 'notes golden fixture differs from Rails'
    end
    closure_entries = [
      { name: 'date_only', method: :post, path: oracle::P,
        body: { note: { body: 'Synthetic note', noted_at: '2026-10-06' } } },
      { name: 'invalid_date', method: :post, path: oracle::P, body: { note: { body: '', noted_at: 'invalid' } } }
    ]
    captured = closure_entries.map do |entry|
      places_record({ auth: :bearer, expect: :own, env: {}, content: oracle::JSON_TYPE }.merge(entry),
                    oracle:, strict: true)
    end
    closure_path = Rails.root.join('app-phoenix/test/fixtures/a12f2a/closure.json')
    closure = closure_path.exist? ? JSON.parse(closure_path.read) : {}
    closure['notes'] = captured
    encoded_closure = "#{Oj.dump(closure.sort.to_h, mode: :strict, indent: 2, float_precision: 0).rstrip}\n"
    FixtureRecording.verify(closure_path, encoded_closure)
  end

  def places_seed(kase)
    oracle = ApiNotesGoldenOracle
    reset!
    allow(DawarichSettings).to receive(:self_hosted?).and_return(true)
    FixtureCleanup.delete!(oracle::TABLES)
    stamps = { created_at: oracle::STAMP, updated_at: oracle::STAMP }
    user = { status: 1, timezone: 'UTC' }.merge(kase[:user] || {})
    places_insert('users', id: oracle::OWNER, email: 'a4rest-notes@example.invalid', api_key: oracle::KEY,
                           status: user[:status], settings: { 'timezone' => user[:timezone] },
                           visits_redetected_at: oracle::STAMP, **stamps)
    places_insert('users', id: oracle::OTHER, email: 'a4rest-note-other@example.invalid', api_key: 'a4rest-notes-other',
                           status: 1, settings: { 'timezone' => 'UTC' }, visits_redetected_at: oracle::STAMP, **stamps)
    [oracle::OWNER, oracle::OTHER].each_with_index do |owner, i|
      places_insert('trips', id: 952_101 + i, user_id: owner, name: 'Synthetic note trip',
                             started_at: '2026-09-01 00:00:00', ended_at: '2026-09-03 23:59:59', **stamps)
      places_insert('areas', id: 952_111 + i, user_id: owner, name: 'Synthetic note area',
                             latitude: 52.52, longitude: 13.405, radius: 100, **stamps)
      places_insert('visits', id: 952_121 + i, user_id: owner, name: 'Synthetic note visit',
                             started_at: '2026-09-01 00:00:00', ended_at: '2026-09-01 01:00:00', duration: 60, **stamps)
      places_insert('places', id: 952_131 + i, user_id: owner, name: 'Synthetic note place',
                              latitude: 52.52, longitude: 13.405, lonlat: 'SRID=4326;POINT(13.405 52.52)', **stamps)
    end
    return if kase[:seed] == :empty

    places_insert('notes', id: 952_201, user_id: oracle::OWNER, title: 'Synthetic note', body: 'Original body',
                           noted_at: '2026-09-01 22:30:00', lonlat: 'SRID=4326;POINT(13.405 52.52)',
                           source_digest: Note.body_digest('Original body'), **stamps)
    places_insert('notes', id: 952_202, user_id: oracle::OWNER, body: 'Newer standalone',
                           noted_at: '2026-09-02 12:00:00', **stamps)
    places_insert('notes', id: 952_204, user_id: oracle::OTHER, body: 'Foreign note',
                           noted_at: '2026-09-03 12:00:00', **stamps)
    [['Trip', 952_101, 952_203, 0], ['Area', 952_111, 952_205, 1],
     ['Visit', 952_121, 952_206, 2], ['Place', 952_131, 952_207, 3]].each do |type, parent, id, minutes|
      places_insert('notes', id:, user_id: oracle::OWNER, body: "Attached #{type}", attachable_type: type,
                             attachable_id: parent, noted_at: "2026-09-01 12:0#{minutes}:00", **stamps)
    end
    places_insert('action_text_rich_texts', id: 952_601, name: 'body', record_type: 'Note', record_id: 952_201,
                                          body: '<p>Synthetic retained rich text</p>', **stamps)
    return unless kase[:seed] == :foreign_collision

    places_insert('notes', id: 952_208, user_id: oracle::OTHER, body: 'Foreign validation collision',
                           attachable_type: 'Trip', attachable_id: 952_101, noted_at: '2026-09-02 12:00:00', **stamps)
  end
end
