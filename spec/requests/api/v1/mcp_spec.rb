# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1::Mcp', type: :request do
  let(:user) { create(:user) }

  before { host! 'localhost' }

  let(:headers) do
    {
      'Authorization' => "Bearer #{user.api_key}",
      'Content-Type' => 'application/json',
      'Accept' => 'application/json'
    }
  end

  def rpc(method, params: nil, id: 1, request_headers: headers)
    payload = { jsonrpc: '2.0', id: id, method: method }
    payload[:params] = params if params

    post '/api/v1/mcp', params: payload.to_json, headers: request_headers
    JSON.parse(response.body) if response.body.present?
  end

  def insert_visits(count, started_at:)
    now = Time.current
    Visit.insert_all!(Array.new(count) do |index|
      {
        user_id: user.id,
        started_at: started_at + (index / 1_000_000.0),
        ended_at: started_at + 1.minute,
        duration: 1,
        name: "Visit #{index}",
        status: 0,
        created_at: now,
        updated_at: now
      }
    end)
  end

  describe 'authentication and discovery' do
    it 'rejects requests without an API key' do
      rpc('initialize', params: { protocolVersion: '2025-11-25', capabilities: {}, clientInfo: {} },
                        request_headers: headers.except('Authorization'))

      expect(response).to have_http_status(:unauthorized)
    end

    it 'initializes a stateless MCP server' do
      result = rpc('initialize', params: {
                     protocolVersion: '2025-11-25',
                     capabilities: {},
                     clientInfo: { name: 'rspec', version: '1.0' }
                   })

      expect(response).to have_http_status(:ok)
      expect(result.dig('result', 'serverInfo', 'name')).to eq('dawarich')
      expect(result.dig('result', 'capabilities')).to include('tools')
    end

    it 'rejects a host outside the configured allowlist' do
      host! 'evil.example'
      payload = { jsonrpc: '2.0', id: 1, method: 'tools/list' }

      post '/api/v1/mcp', params: payload.to_json, headers: headers

      expect(response).to have_http_status(:forbidden)
    end

    it 'rejects output that drifts from the declared schema' do
      invalid_response = MCP::Tool::Response.new(
        [{ type: 'text', text: '{}' }],
        structured_content: { point: { velocity: 'not-a-number' } }
      )
      allow(Mcp::GetLatestLocationTool).to receive(:call).and_return(invalid_response)

      result = rpc('tools/call', params: { name: 'get_latest_location', arguments: {} })

      expect(result).not_to have_key('result')
      expect(result.dig('error', 'message')).to eq('Internal error')
    end

    it 'advertises only read-only MVP tools' do
      result = rpc('tools/list')
      tools = result.dig('result', 'tools')

      expect(tools.pluck('name')).to contain_exactly('get_timeline', 'get_latest_location')
      expect(tools).to all(include('annotations' => include(
        'readOnlyHint' => true,
        'destructiveHint' => false,
        'idempotentHint' => true,
        'openWorldHint' => false
      )))
    end
  end

  describe 'get_timeline' do
    let(:day) { Time.zone.parse('2025-01-15 00:00:00') }
    let(:place) { create(:place, user: user, name: 'Home') }

    before do
      create(:visit,
             user: user,
             place: place,
             name: 'Home',
             started_at: day + 10.hours,
             ended_at: day + 12.hours,
             duration: 120)
    end

    it 'returns timeline days as structured content' do
      result = rpc('tools/call', params: {
                     name: 'get_timeline',
                     arguments: { start_at: day.iso8601, end_at: (day + 1.day).iso8601 }
                   })

      expect(response).to have_http_status(:ok)
      expect(result.dig('result', 'isError')).to be(false)
      entry = result.dig('result', 'structuredContent', 'days', 0, 'entries', 0)
      expect(entry).to include('type' => 'visit', 'name' => 'Home')
      expect(entry).not_to include('editable_name', 'place_id', 'suggested_places')
    end

    it 'treats a date-only range as the complete local day' do
      insert_visits(1, started_at: day.end_of_day)

      result = rpc('tools/call', params: {
                     name: 'get_timeline',
                     arguments: { start_at: '2025-01-15', end_at: '2025-01-15' }
                   })
      names = result.dig('result', 'structuredContent', 'days', 0, 'entries').pluck('name')

      expect(names).to contain_exactly('Home', 'Visit 0')
    end

    it 'does not expose another users timeline' do
      other_user = create(:user)
      other_place = create(:place, user: other_user, name: 'Other home')
      create(:visit,
             user: other_user,
             place: other_place,
             name: 'Other home',
             started_at: day + 9.hours,
             ended_at: day + 10.hours,
             duration: 60)

      result = rpc('tools/call', params: {
                     name: 'get_timeline',
                     arguments: { start_at: day.iso8601, end_at: (day + 1.day).iso8601 }
                   })
      names = result.dig('result', 'structuredContent', 'days').flat_map do |timeline_day|
        timeline_day.fetch('entries').filter_map { |entry| entry['name'] }
      end

      expect(names).to contain_exactly('Home')
    end

    it 'returns a tool error for malformed or oversized ranges' do
      invalid = rpc('tools/call', params: {
                      name: 'get_timeline',
                      arguments: { start_at: '', end_at: day.iso8601 }
                    })
      oversized = rpc('tools/call', id: 2, params: {
                        name: 'get_timeline',
                        arguments: { start_at: '2025-01-01', end_at: '2025-01-08' }
                      })

      impossible = rpc('tools/call', id: 3, params: {
                         name: 'get_timeline',
                         arguments: { start_at: '2025-02-30T00:00:00Z', end_at: '2025-03-03T00:00:00Z' }
                       })

      expect(invalid.dig('result', 'isError')).to be(true)
      expect(oversized.dig('result', 'isError')).to be(true)
      expect(impossible.dig('result', 'isError')).to be(true)
    end

    it 'allows seven local calendar days across a DST transition' do
      user.update!(settings: user.settings.merge('timezone' => 'America/New_York'))

      result = rpc('tools/call', params: {
                     name: 'get_timeline',
                     arguments: { start_at: '2025-10-27', end_at: '2025-11-02' }
                   })

      expect(result.dig('result', 'isError')).to be(false)
    end

    it 'rejects more than 500 database entries before assembly' do
      insert_visits(500, started_at: day + 8.hours)
      expect(Timeline::DayAssembler).not_to receive(:new)

      result = rpc('tools/call', params: {
                     name: 'get_timeline',
                     arguments: { start_at: day.iso8601, end_at: (day + 1.day).iso8601 }
                   })

      expect(result.dig('result', 'isError')).to be(true)
    end

    it 'counts a track ending at midnight only on its start day' do
      user.update!(settings: user.settings.merge('timezone' => 'UTC'))
      range_start = Time.utc(2025, 4, 27)
      insert_visits(499, started_at: range_start + 8.hours)
      create(:track,
             user: user,
             start_at: Time.utc(2025, 4, 27, 22),
             end_at: Time.utc(2025, 4, 28, 0))

      result = rpc('tools/call', params: {
                     name: 'get_timeline',
                     arguments: { start_at: '2025-04-27', end_at: '2025-04-28' }
                   })

      expect(result.dig('result', 'isError')).to be(false)
      expect(result.dig('result', 'structuredContent', 'days').sum { |value| value['entries'].size }).to eq(500)
    end

    it 'allows exactly 500 database entries' do
      insert_visits(499, started_at: day + 8.hours)

      result = rpc('tools/call', params: {
                     name: 'get_timeline',
                     arguments: { start_at: day.iso8601, end_at: (day + 1.day).iso8601 }
                   })

      expect(result.dig('result', 'isError')).to be(false)
      expect(result.dig('result', 'structuredContent', 'days').sum { |value| value['entries'].size }).to eq(500)
    end
  end

  describe 'get_latest_location' do
    it 'returns the newest visible non-anomalous point for the authenticated user' do
      create(:point, user: user, timestamp: 2.hours.ago.to_i, longitude: 13.40, latitude: 52.50)
      expected = create(:point, user: user, timestamp: 1.hour.ago.to_i, longitude: 13.41, latitude: 52.51,
                                tracker_id: 'phone', velocity: '12.5')
      create(:point, user: user, timestamp: Time.current.to_i, longitude: 13.42, latitude: 52.52, anomaly: true)
      create(:point, user: create(:user), timestamp: 10.minutes.ago.to_i, longitude: 1.0, latitude: 2.0)

      result = rpc('tools/call', params: { name: 'get_latest_location', arguments: {} })
      point = result.dig('result', 'structuredContent', 'point')

      expect(point).to include(
        'id' => expected.id,
        'latitude' => 52.51,
        'longitude' => 13.41,
        'tracker_id' => 'phone',
        'velocity' => 12.5
      )
      expect(Time.iso8601(point.fetch('recorded_at')).to_i).to eq(expected.timestamp)
    end

    it 'respects the authenticated users plan data window' do
      allow(DawarichSettings).to receive(:self_hosted?).and_return(false)
      user.update!(plan: :lite)
      create(:point, user: user, timestamp: 13.months.ago.to_i, longitude: 1.0, latitude: 2.0)
      expected = create(:point, user: user, timestamp: 1.day.ago.to_i, longitude: 3.0, latitude: 4.0)

      result = rpc('tools/call', params: { name: 'get_latest_location', arguments: {} })

      expect(result.dig('result', 'structuredContent', 'point', 'id')).to eq(expected.id)
    end

    it 'returns null when the user has no visible points' do
      create(:point, user: create(:user))

      result = rpc('tools/call', params: { name: 'get_latest_location', arguments: {} })

      expect(result.dig('result', 'structuredContent')).to eq('point' => nil)
    end
  end
end
