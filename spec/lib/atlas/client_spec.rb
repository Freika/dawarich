# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Atlas::Client do
  subject(:client) { described_class.new(configuration) }

  let(:configuration) do
    Atlas::Configuration.new.tap do |config|
      config.url = 'http://atlas.test'
      config.api_key = 'test-key'
    end
  end

  let(:geocode_url) { 'http://atlas.test/api/v1/geocode/batch' }
  let(:reverse_url) { 'http://atlas.test/api/v1/reverse/batch' }

  describe '#geocode_batch' do
    let(:response_body) do
      {
        results: [
          {
            query: 'Brandenburg Gate, Berlin',
            matches: [
              {
                name: 'Brandenburg Gate',
                display_name: 'Brandenburg Gate, Pariser Platz, Berlin, 10117, Germany',
                lat: 52.5162746,
                lon: 13.3777041,
                type: 'tourism',
                address: { city: 'Berlin', country: 'Germany', country_code: 'de' }
              }
            ]
          }
        ]
      }.to_json
    end

    before { stub_request(:post, geocode_url).to_return(status: 200, body: response_body) }

    it 'authenticates with a bearer token' do
      client.geocode_batch([{ q: 'Brandenburg Gate, Berlin', limit: 1 }])

      expect(a_request(:post, geocode_url).with(headers: { 'Authorization' => 'Bearer test-key' })).to have_been_made
    end

    it 'posts the queries payload' do
      client.geocode_batch([{ q: 'Berlin', limit: 1 }])

      expect(a_request(:post, geocode_url).with(body: { queries: [{ q: 'Berlin', limit: 1 }] })).to have_been_made
    end

    it 'normalizes bare string queries into { q: ... }' do
      client.geocode_batch(['Berlin'])

      expect(a_request(:post, geocode_url).with(body: { queries: [{ q: 'Berlin' }] })).to have_been_made
    end

    it 'includes lang when provided' do
      client.geocode_batch(['Berlin'], lang: 'de')

      expect(a_request(:post, geocode_url).with(body: { queries: [{ q: 'Berlin' }], lang: 'de' })).to have_been_made
    end

    it 'returns one match list per query' do
      expect(client.geocode_batch(['Brandenburg Gate, Berlin']).size).to eq(1)
    end

    it 'wraps matches in Atlas::Result' do
      matches = client.geocode_batch(['Brandenburg Gate, Berlin']).first

      expect(matches.first).to be_an(Atlas::Result)
    end

    it 'exposes the resolved city' do
      matches = client.geocode_batch(['Brandenburg Gate, Berlin']).first

      expect(matches.first.city).to eq('Berlin')
    end

    it 'exposes the resolved coordinates' do
      matches = client.geocode_batch(['Brandenburg Gate, Berlin']).first

      expect(matches.first.coordinates).to eq([52.5162746, 13.3777041])
    end
  end

  describe '#reverse_geocode_batch' do
    let(:response_body) do
      {
        results: [
          {
            lat: 52.5162746,
            lon: 13.3777041,
            result: {
              name: 'Brandenburg Gate',
              display_name: 'Brandenburg Gate, Pariser Platz, Berlin, 10117, Germany',
              address: { city: 'Berlin', country: 'Germany', country_code: 'de' }
            }
          }
        ]
      }.to_json
    end

    before { stub_request(:post, reverse_url).to_return(status: 200, body: response_body) }

    it 'posts coordinate pairs to the reverse batch endpoint' do
      client.reverse_geocode_batch([[52.5162746, 13.3777041]])

      expected = { coordinates: [{ lat: 52.5162746, lon: 13.3777041 }] }
      expect(a_request(:post, reverse_url).with(body: expected)).to have_been_made
    end

    it 'returns one entry per coordinate' do
      expect(client.reverse_geocode_batch([[52.5162746, 13.3777041]]).size).to eq(1)
    end

    it 'wraps each result in Atlas::Result' do
      expect(client.reverse_geocode_batch([[52.5162746, 13.3777041]]).first).to be_an(Atlas::Result)
    end

    it 'exposes the resolved country' do
      expect(client.reverse_geocode_batch([[52.5162746, 13.3777041]]).first.country).to eq('Germany')
    end

    it 'yields nil for coordinates with no result' do
      body = { results: [{ lat: 0.0, lon: 0.0, result: nil }] }.to_json
      stub_request(:post, reverse_url).to_return(status: 200, body: body)

      expect(client.reverse_geocode_batch([[0.0, 0.0]])).to eq([nil])
    end
  end

  describe 'error handling' do
    it 'raises Unauthorized on 401' do
      stub_request(:post, reverse_url).to_return(status: 401, body: { error: { message: 'Invalid API key' } }.to_json)

      expect { client.reverse_geocode_batch([[1, 2]]) }.to raise_error(Atlas::Client::Unauthorized, /Invalid API key/)
    end

    it 'raises RateLimited on 429' do
      stub_request(:post, geocode_url).to_return(status: 429, body: { error: { message: 'slow down' } }.to_json)

      expect { client.geocode_batch(['x']) }.to raise_error(Atlas::Client::RateLimited)
    end

    it 'raises ServerError on 500' do
      stub_request(:post, geocode_url).to_return(status: 500, body: 'boom')

      expect { client.geocode_batch(['x']) }.to raise_error(Atlas::Client::ServerError)
    end

    it 'wraps connection timeouts in Atlas::Client::Error' do
      stub_request(:post, geocode_url).to_timeout

      expect { client.geocode_batch(['x']) }.to raise_error(Atlas::Client::Error, /Atlas request failed/)
    end

    it 'wraps connection failures in Atlas::Client::Error' do
      stub_request(:post, reverse_url).to_raise(Faraday::ConnectionFailed.new('refused'))

      expect { client.reverse_geocode_batch([[1, 2]]) }.to raise_error(Atlas::Client::Error, /Atlas request failed/)
    end

    it 'raises Error and logs on an unhandled status (e.g. 403)' do
      stub_request(:post, geocode_url).to_return(status: 403, body: { error: { message: 'Forbidden' } }.to_json)
      allow(Rails.logger).to receive(:warn)

      expect { client.geocode_batch(['x']) }.to raise_error(Atlas::Client::Error, /Forbidden/)
      expect(Rails.logger).to have_received(:warn).with(/Atlas request returned 403/)
    end

    it 'falls back to the default message when the error body is not a JSON object' do
      stub_request(:post, geocode_url).to_return(status: 404, body: '"plain string"')

      expect { client.geocode_batch(['x']) }.to raise_error(Atlas::Client::Error, /Unexpected response: 404/)
    end
  end

  describe 'authentication' do
    it 'omits the Authorization header when no api key is configured' do
      configuration.api_key = nil
      stub_request(:post, geocode_url).to_return(status: 200, body: { results: [] }.to_json)

      client.geocode_batch(['Berlin'])

      expect(a_request(:post, geocode_url).with { |req| !req.headers.key?('Authorization') }).to have_been_made
    end
  end

  describe 'query validation' do
    it 'raises ArgumentError when a Hash query has no :q' do
      expect { client.geocode_batch([{ limit: 1 }]) }.to raise_error(ArgumentError, /missing :q/)
    end
  end

  describe 'tool gating' do
    let(:configuration) do
      Atlas::Configuration.new.tap do |config|
        config.url = 'http://atlas.test'
        config.api_key = 'test-key'
        config.enabled_tools = %i[map_matching]
      end
    end

    it 'raises ToolDisabled from geocode_batch when geocoding is not enabled' do
      expect { client.geocode_batch(['Berlin']) }
        .to raise_error(Atlas::Client::ToolDisabled, /geocoding/)
    end

    it 'raises ToolDisabled from reverse_geocode_batch when geocoding is not enabled' do
      expect { client.reverse_geocode_batch([[52.5, 13.4]]) }
        .to raise_error(Atlas::Client::ToolDisabled, /geocoding/)
    end

    it 'does not make an HTTP request when the tool is disabled' do
      stub = stub_request(:post, geocode_url)

      begin
        client.geocode_batch(['Berlin'])
      rescue Atlas::Client::ToolDisabled
        # expected
      end

      expect(stub).not_to have_been_requested
    end
  end

  describe 'Geocoder::ApiClient drop-in compatibility' do
    it '#search returns a results hash built from the batch endpoint' do
      stub_request(:post, geocode_url)
        .to_return(status: 200, body: { results: [{ query: 'Berlin', matches: [{ name: 'Berlin' }] }] }.to_json)

      expect(client.search('Berlin', limit: 5)['results'].first['name']).to eq('Berlin')
    end

    it '#search queries the batch endpoint with the requested limit' do
      body = { results: [{ query: 'Berlin', matches: [] }] }.to_json
      stub_request(:post, geocode_url).to_return(status: 200, body: body)
      client.search('Berlin', limit: 5)

      expected = { queries: [{ q: 'Berlin', limit: 5 }] }
      expect(a_request(:post, geocode_url).with(body: expected)).to have_been_made
    end

    it '#reverse returns a results hash built from the reverse batch endpoint' do
      body = { results: [{ lat: 52.5, lon: 13.4, result: { address: { country: 'Germany' } } }] }.to_json
      stub_request(:post, reverse_url).to_return(status: 200, body: body)

      expect(client.reverse(52.5, 13.4)['results'].first['address']['country']).to eq('Germany')
    end
  end
end
