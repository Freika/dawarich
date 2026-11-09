# frozen_string_literal: true

require 'rails_helper'

RSpec.describe AirTrail::Client do
  let(:client) { described_class.new('https://airtrail.example', 'secret-key') }

  describe '#flights' do
    it 'GETs the flight list with a bearer token and returns the flights array' do
      stub = stub_request(:get, 'https://airtrail.example/api/flight/list?scope=mine')
             .with(headers: { 'Authorization' => 'Bearer secret-key' })
             .to_return(status: 200, body: { success: true, flights: [{ 'id' => 1 }] }.to_json,
                        headers: { 'Content-Type' => 'application/json' })

      expect(client.flights).to eq([{ 'id' => 1 }])
      expect(stub).to have_been_requested
    end

    it 'strips a trailing slash from the url' do
      stub = stub_request(:get, 'https://airtrail.example/api/flight/list?scope=mine')
             .to_return(status: 200, body: { success: true, flights: [] }.to_json,
                        headers: { 'Content-Type' => 'application/json' })

      described_class.new('https://airtrail.example/', 'k').flights
      expect(stub).to have_been_requested
    end

    it 'raises AirTrail::Client::Error on non-2xx' do
      stub_request(:get, 'https://airtrail.example/api/flight/list?scope=mine')
        .to_return(status: 401, body: 'nope')

      expect { client.flights }.to raise_error(AirTrail::Client::Error)
    end

    it 'refuses a URL that resolves to a blocked address without sending a request' do
      stub_host_addresses('airtrail.example', '169.254.169.254')
      request = stub_request(:get, 'https://airtrail.example/api/flight/list?scope=mine')

      expect { client.flights }.to raise_error(AirTrail::Client::Error)
      expect(request).not_to have_been_requested
    end

    it 'does not follow a redirect and keeps its status' do
      stub_request(:get, 'https://airtrail.example/api/flight/list?scope=mine')
        .to_return(status: 301, headers: { 'Location' => 'https://elsewhere.example/' })
      followed = stub_request(:get, 'https://elsewhere.example/')

      expect { client.flights }.to raise_error(AirTrail::Client::Error) { |error| expect(error.status).to eq(301) }
      expect(followed).not_to have_been_requested
    end

    it 'raises AirTrail::Client::Error when the connection is refused' do
      stub_request(:get, 'https://airtrail.example/api/flight/list?scope=mine')
        .to_raise(Errno::ECONNREFUSED)

      expect { client.flights }.to raise_error(AirTrail::Client::Error)
    end

    it 'raises AirTrail::Client::Error when the host cannot be resolved' do
      stub_request(:get, 'https://airtrail.example/api/flight/list?scope=mine')
        .to_raise(SocketError.new('getaddrinfo: nodename nor servname provided'))

      expect { client.flights }.to raise_error(AirTrail::Client::Error)
    end

    it 'raises AirTrail::Client::Error when success is false' do
      stub_request(:get, 'https://airtrail.example/api/flight/list?scope=mine')
        .to_return(status: 200, body: { success: false }.to_json,
                   headers: { 'Content-Type' => 'application/json' })

      expect { client.flights }.to raise_error(AirTrail::Client::Error)
    end
  end

  describe '#track_summaries' do
    it 'pages through the v1 flight list and maps each flight id to its track summary' do
      summary = { 'pointCount' => 120, 'updatedAt' => '2026-10-20T08:00:00.000Z' }
      first = stub_request(:get, 'https://airtrail.example/api/v1/flights?limit=100')
              .with(headers: { 'Authorization' => 'Bearer secret-key' })
              .to_return(status: 200, body: { data: [{ id: 1, track: summary }], page: { nextCursor: 'c2' } }.to_json,
                         headers: { 'Content-Type' => 'application/json' })
      second = stub_request(:get, 'https://airtrail.example/api/v1/flights?limit=100&cursor=c2')
               .to_return(status: 200, body: { data: [{ id: 2, track: nil }], page: { nextCursor: nil } }.to_json,
                          headers: { 'Content-Type' => 'application/json' })

      expect(client.track_summaries).to eq(1 => summary, 2 => nil)
      expect(first).to have_been_requested
      expect(second).to have_been_requested
    end

    it 'skips malformed flight entries and page data' do
      stub_request(:get, 'https://airtrail.example/api/v1/flights?limit=100')
        .to_return(status: 200, headers: { 'Content-Type' => 'application/json' },
                   body: { data: [{ id: 1, track: nil }, 'junk', [2]], page: ['oops'] }.to_json)

      expect(client.track_summaries).to eq(1 => nil)
    end

    it 'raises AirTrail::Client::Error when the response is not a JSON object' do
      stub_request(:get, 'https://airtrail.example/api/v1/flights?limit=100')
        .to_return(status: 200, body: '[]', headers: { 'Content-Type' => 'application/json' })

      expect { client.track_summaries }.to raise_error(AirTrail::Client::Error)
    end

    it 'raises AirTrail::Client::Error when AirTrail has no v1 API' do
      stub_request(:get, 'https://airtrail.example/api/v1/flights?limit=100').to_return(status: 404)

      expect { client.track_summaries }.to raise_error(AirTrail::Client::Error)
    end
  end

  describe '#track' do
    it 'returns the track of a flight' do
      track = { 'flightId' => 7, 'coordinates' => [[13.5, 52.4, 30], [2.5, 49.0, 120]] }
      stub_request(:get, 'https://airtrail.example/api/v1/flights/7/track')
        .with(headers: { 'Authorization' => 'Bearer secret-key' })
        .to_return(status: 200, body: { data: track }.to_json, headers: { 'Content-Type' => 'application/json' })

      expect(client.track(7)).to eq(track)
    end

    it 'returns nil when the flight has no track' do
      stub_request(:get, 'https://airtrail.example/api/v1/flights/7/track')
        .to_return(status: 200, body: { data: nil }.to_json, headers: { 'Content-Type' => 'application/json' })

      expect(client.track(7)).to be_nil
    end

    it 'raises AirTrail::Client::Error when the key lacks the tracks scope' do
      stub_request(:get, 'https://airtrail.example/api/v1/flights/7/track').to_return(status: 403)

      expect { client.track(7) }.to raise_error(AirTrail::Client::Error)
    end
  end
end
