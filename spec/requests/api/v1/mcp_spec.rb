# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1::Mcp', type: :request do
  let(:user) { create(:user) }

  let(:headers) do
    {
      'Authorization' => "Bearer #{user.api_key}",
      'Content-Type' => 'application/json',
      'Accept' => 'application/json'
    }
  end

  def rpc(method, params: nil, id: 1, request_headers: headers, path: '/api/v1/mcp')
    payload = { jsonrpc: '2.0', id: id, method: method }
    payload[:params] = params if params

    post path, params: payload.to_json, headers: request_headers
    JSON.parse(response.body) if response.body.present?
  end

  def call_tool(name, arguments, id: 1)
    rpc('tools/call', id: id, params: { name: name, arguments: arguments })
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

    it 'rejects an API key passed as a query parameter' do
      rpc('tools/list', request_headers: headers.except('Authorization'),
                        path: "/api/v1/mcp?api_key=#{user.api_key}")

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

    it 'accepts requests addressed to a non-loopback host' do
      host! 'dawarich.example.com'

      result = rpc('tools/list')

      expect(response).to have_http_status(:ok)
      expect(result.dig('result', 'tools')).to be_present
    end

    it 'rejects output that drifts from the declared schema' do
      invalid_response = MCP::Tool::Response.new(
        [{ type: 'text', text: '{}' }],
        structured_content: { point: { velocity: 'not-a-number' } }
      )
      allow(McpTools::GetLatestLocation).to receive(:call).and_return(invalid_response)

      result = call_tool('get_latest_location', {})

      expect(result).not_to have_key('result')
      expect(result.dig('error', 'message')).to eq('Internal error')
    end

    it 'advertises only read-only tools' do
      result = rpc('tools/list')
      tools = result.dig('result', 'tools')

      expect(tools.pluck('name')).to contain_exactly('get_timeline', 'get_latest_location', 'search_visits')
      expect(tools).to all(include('annotations' => include(
        'readOnlyHint' => true,
        'destructiveHint' => false,
        'idempotentHint' => true,
        'openWorldHint' => false
      )))
    end

    it 'explains visit statuses in the visit tool descriptions' do
      tools = rpc('tools/list').dig('result', 'tools').index_by { |tool| tool['name'] }

      expect(tools.values_at('get_timeline', 'search_visits').pluck('description'))
        .to all(include('suggested').and(include('confirmed')))
    end

    it 'tells the model not to add up journey continuation rows' do
      tools = rpc('tools/list').dig('result', 'tools').index_by { |tool| tool['name'] }

      expect(tools.dig('get_timeline', 'description')).to include('continuation_of_date')
    end

    {
      'get_timeline' => { start_at: '2025-01-15', end_at: '2025-01-15' },
      'get_latest_location' => {},
      'search_visits' => { query: 'home' }
    }.each do |tool_name, arguments|
      it "returns a tool error for an unknown #{tool_name} argument" do
        result = call_tool(tool_name, arguments.merge(timezone: 'UTC'))

        expect(result.dig('result', 'isError')).to be(true)
      end
    end

    it 'accepts DELETE as a no-op because the server keeps no sessions' do
      delete '/api/v1/mcp', headers: headers

      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)).to eq('success' => true)
    end

    it 'answers GET with 405 because the server offers no event stream' do
      get '/api/v1/mcp', headers: headers.merge('Accept' => 'text/event-stream')

      expect(response).to have_http_status(:method_not_allowed)
    end
  end

  describe 'error reporting' do
    before { allow(Rails.logger).to receive(:error) }

    it 'logs tool exceptions' do
      allow(McpTools::GetLatestLocation).to receive(:call).and_raise(RuntimeError, 'tool exploded')

      call_tool('get_latest_location', {})

      expect(Rails.logger).to have_received(:error).with(a_string_including('tool exploded'))
    end

    it 'logs transport exceptions reported through the global MCP configuration' do
      MCP.configuration.exception_reporter.call(RuntimeError.new('transport exploded'), { request: '{}' })

      expect(Rails.logger).to have_received(:error).with(a_string_including('transport exploded'))
    end
  end

  describe 'plan access on Dawarich Cloud' do
    before { allow(DawarichSettings).to receive(:self_hosted?).and_return(false) }

    it 'rejects Lite users' do
      user.update!(plan: :lite)

      rpc('tools/list')

      expect(response).to have_http_status(:forbidden)
      expect(JSON.parse(response.body)['error']).to eq('pro_plan_required')
    end

    it 'allows Pro users' do
      user.update!(plan: :pro)

      rpc('tools/list')

      expect(response).to have_http_status(:ok)
    end

    it 'allows Family users' do
      user.update!(plan: :family)

      rpc('tools/list')

      expect(response).to have_http_status(:ok)
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

    def timeline(start_at: day.iso8601, end_at: (day + 1.day).iso8601)
      call_tool('get_timeline', { start_at: start_at, end_at: end_at })
    end

    def entry_count(result)
      result.dig('result', 'structuredContent', 'days').sum { |value| value['entries'].size }
    end

    it 'returns timeline days as structured content' do
      result = timeline

      expect(response).to have_http_status(:ok)
      expect(result.dig('result', 'isError')).to be(false)
      entry = result.dig('result', 'structuredContent', 'days', 0, 'entries', 0)
      expect(entry).to include('type' => 'visit', 'name' => 'Home', 'duration_minutes' => 120.0)
      expect(entry).not_to include('editable_name', 'place_id', 'suggested_places')
    end

    it 'reports journey durations in minutes' do
      create(:track, user: user, start_at: day + 13.hours, end_at: day + 13.hours + 30.minutes, duration: 1800)

      journey = timeline.dig('result', 'structuredContent', 'days', 0, 'entries').find do |entry|
        entry['type'] == 'journey'
      end

      expect(journey).to include('duration_minutes' => 30.0)
      expect(journey).not_to have_key('duration_seconds')
    end

    it 'treats a date-only range as the complete local day' do
      insert_visits(1, started_at: day.end_of_day)

      result = timeline(start_at: '2025-01-15', end_at: '2025-01-15')
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

      names = timeline.dig('result', 'structuredContent', 'days').flat_map do |timeline_day|
        timeline_day.fetch('entries').filter_map { |entry| entry['name'] }
      end

      expect(names).to contain_exactly('Home')
    end

    it 'returns a tool error for malformed or oversized ranges' do
      invalid = timeline(start_at: '')
      oversized = timeline(start_at: '2025-01-01', end_at: '2025-01-08')
      impossible = timeline(start_at: '2025-02-30T00:00:00Z', end_at: '2025-03-03T00:00:00Z')
      reversed = timeline(start_at: '2025-01-10', end_at: '2025-01-09')

      expect(invalid.dig('result', 'isError')).to be(true)
      expect(oversized.dig('result', 'isError')).to be(true)
      expect(impossible.dig('result', 'isError')).to be(true)
      expect(reversed.dig('result', 'isError')).to be(true)
    end

    it 'returns no days for a range without visits or journeys' do
      result = timeline(start_at: '2024-06-01', end_at: '2024-06-02').fetch('result')

      expect(result['isError']).to be(false)
      expect(result['structuredContent']).to eq('days' => [])
    end

    it 'allows seven local calendar days across a DST transition' do
      user.update!(settings: user.settings.merge('timezone' => 'America/New_York'))

      result = timeline(start_at: '2025-10-27', end_at: '2025-11-02')

      expect(result.dig('result', 'isError')).to be(false)
    end

    it 'rejects a timeline with more than 250 entries' do
      insert_visits(250, started_at: day + 8.hours)

      result = timeline.fetch('result')

      expect(result['isError']).to be(true)
      expect(result.dig('content', 0, 'text')).to include('more than 250 entries')
    end

    it 'returns tool errors without structured content that would break the output schema' do
      result = timeline(start_at: '2025-01-01', end_at: '2025-01-08').fetch('result')

      expect(result['isError']).to be(true)
      expect(result).not_to have_key('structuredContent')
      expect(result.dig('content', 0, 'text')).to include('7 calendar days')
    end

    it 'reports the per-day share of a journey that continues past midnight' do
      user.update!(settings: user.settings.merge('timezone' => 'UTC'))
      create(:track, user: user, start_at: Time.utc(2025, 4, 27, 22), end_at: Time.utc(2025, 4, 28, 2),
                     duration: 14_400, distance: 4000)

      days = timeline(start_at: '2025-04-27', end_at: '2025-04-28').dig('result', 'structuredContent', 'days')
      journeys = days.to_h do |timeline_day|
        [timeline_day['date'], timeline_day['entries'].find { |entry| entry['type'] == 'journey' }]
      end

      expect(journeys['2025-04-27']).to include('continuation_of_date' => nil, 'duration_minutes' => 240.0)
      expect(journeys['2025-04-28']).to include('continuation_of_date' => '2025-04-27',
                                                'duration_minutes' => 120.0, 'distance' => 2.0)
    end

    it 'allows exactly 250 entries' do
      insert_visits(249, started_at: day + 8.hours)

      result = timeline

      expect(result.dig('result', 'isError')).to be(false)
      expect(entry_count(result)).to eq(250)
    end

    it 'counts a track ending at midnight only on its start day' do
      user.update!(settings: user.settings.merge('timezone' => 'UTC'))
      insert_visits(249, started_at: Time.utc(2025, 4, 27, 8))
      create(:track, user: user, start_at: Time.utc(2025, 4, 27, 22), end_at: Time.utc(2025, 4, 28, 0))

      result = timeline(start_at: '2025-04-27', end_at: '2025-04-28')

      expect(result.dig('result', 'isError')).to be(false)
      expect(entry_count(result)).to eq(250)
    end
  end

  describe 'search_visits' do
    let(:leipzig) { create(:place, user: user, name: 'Hauptbahnhof', city: 'Leipzig', country: 'Germany') }

    def visit_at(started_at, owner: user, **attributes)
      create(:visit, user: owner, area: nil, status: :confirmed, name: 'Somewhere',
                     started_at: started_at, ended_at: started_at + 1.hour, duration: 60, **attributes)
    end

    def search(arguments)
      call_tool('search_visits', arguments).fetch('result')
    end

    it 'finds visits by place city, newest first, with the total match count' do
      older = visit_at(10.days.ago, place: leipzig)
      newer = visit_at(3.days.ago, place: leipzig)
      visit_at(1.day.ago, name: 'Home')

      result = search(query: 'leipzig')
      visits = result.dig('structuredContent', 'visits')

      expect(result['isError']).to be(false)
      expect(result.dig('structuredContent', 'total_count')).to eq(2)
      expect(visits.map { |visit| Time.iso8601(visit['started_at']).to_i })
        .to eq([newer.started_at.to_i, older.started_at.to_i])
      expect(visits.first).to include(
        'type' => 'visit',
        'duration_minutes' => 60.0,
        'place' => include('name' => 'Hauptbahnhof', 'city' => 'Leipzig', 'country' => 'Germany')
      )
    end

    it 'matches visit, place, country and area names' do
      visit_at(4.days.ago, name: 'Grandma')
      visit_at(3.days.ago, place: create(:place, user: user, name: 'Kaffeehaus Riquet'))
      visit_at(2.days.ago, place: create(:place, user: user, name: 'Stall', country: 'Austria'))
      visit_at(1.day.ago, area: create(:area, user: user, name: 'Office'))

      expect(search(query: 'grand').dig('structuredContent', 'total_count')).to eq(1)
      expect(search(query: 'riquet').dig('structuredContent', 'total_count')).to eq(1)
      expect(search(query: 'austria').dig('structuredContent', 'total_count')).to eq(1)
      expect(search(query: 'office').dig('structuredContent', 'total_count')).to eq(1)
    end

    it 'excludes declined visits and other users visits' do
      visit_at(2.days.ago, place: leipzig)
      visit_at(1.day.ago, place: leipzig, status: :declined)
      other_user = create(:user)
      visit_at(1.day.ago, owner: other_user,
                          place: create(:place, user: other_user, name: 'Hbf', city: 'Leipzig'))

      expect(search(query: 'Leipzig').dig('structuredContent', 'total_count')).to eq(1)
    end

    it 'limits the returned visits but keeps the total match count' do
      3.times { |index| visit_at((index + 1).days.ago, place: leipzig) }

      result = search(query: 'leipzig', limit: 2)

      expect(result.dig('structuredContent', 'total_count')).to eq(3)
      expect(result.dig('structuredContent', 'visits').size).to eq(2)
    end

    it 'treats LIKE wildcards in the query literally' do
      visit_at(1.day.ago, place: leipzig)

      expect(search(query: '%%').dig('structuredContent', 'total_count')).to eq(0)
    end

    it 'rejects queries shorter than two characters' do
      expect(search(query: 'L')['isError']).to be(true)
    end
  end

  describe 'get_latest_location' do
    it 'returns the newest visible non-anomalous point for the authenticated user' do
      create(:point, user: user, timestamp: 2.hours.ago.to_i, longitude: 13.40, latitude: 52.50)
      expected = create(:point, user: user, timestamp: 1.hour.ago.to_i, longitude: 13.41, latitude: 52.51,
                                tracker_id: 'phone', velocity: '12.5')
      create(:point, user: user, timestamp: Time.current.to_i, longitude: 13.42, latitude: 52.52, anomaly: true)
      create(:point, user: create(:user), timestamp: 10.minutes.ago.to_i, longitude: 1.0, latitude: 2.0)

      point = call_tool('get_latest_location', {}).dig('result', 'structuredContent', 'point')

      expect(point).to include(
        'id' => expected.id,
        'latitude' => 52.51,
        'longitude' => 13.41,
        'tracker_id' => 'phone',
        'velocity' => 12.5
      )
      expect(Time.iso8601(point.fetch('recorded_at')).to_i).to eq(expected.timestamp)
    end

    it 'returns null when the user has no visible points' do
      create(:point, user: create(:user))

      result = call_tool('get_latest_location', {})

      expect(result.dig('result', 'structuredContent')).to eq('point' => nil)
    end
  end
end
