# frozen_string_literal: true

require 'rails_helper'

RSpec.describe MapMatching::Atlas::Client do
  let(:base_url) { 'https://atlas.example.test' }

  subject(:client) { described_class.new(base_url:) }

  before do
    allow(Resolv).to receive(:getaddress).with('atlas.example.test').and_return('93.184.216.34')
  end

  it 'reads health and routing readiness' do
    stub_request(:get, 'https://atlas.example.test/api/v1/health').to_return(
      status: 200,
      body: { data: { status: 'degraded', capabilities: { routing: 'up' } }, meta: {} }.to_json
    )

    expect(client.health).to eq(status: 'degraded', routing: 'up')
  end

  it 'reads version and revision' do
    stub_request(:get, 'https://atlas.example.test/api/v1/version').to_return(
      status: 200,
      body: { data: { version: '0.6.0', revision: 'abc123' } }.to_json
    )

    expect(client.version).to eq(version: '0.6.0', revision: 'abc123')
  end

  it 'posts the stable map-matching contract and returns geometry and diagnostics' do
    request = stub_request(:post, 'https://atlas.example.test/api/v1/map-match')
              .with(body: hash_including(
                'mode' => 'bicycle', 'shape_match' => 'map_snap',
                'format' => 'geojson', 'include_directions' => false,
                'shape' => [{ 'lat' => 52.5, 'lon' => 13.4, 'time' => 100, 'accuracy' => 5 }]
              ))
              .to_return(
                status: 200,
                body: {
                  data: {
                    geometry: { type: 'LineString', coordinates: [[13.4, 52.5], [13.41, 52.51]] },
                    stats: { matched: 2, unmatched: 0 }
                  },
                  meta: { mode: 'bicycle' }
                }.to_json
              )

    result = client.map_match(
      shape: [{ lat: 52.5, lon: 13.4, time: 100, accuracy: 5 }],
      mode: 'bicycle'
    )

    expect(result.geometry['type']).to eq('LineString')
    expect(result.stats['matched']).to eq(2)
    expect(request).to have_been_requested
  end

  it 'classifies terminal input errors without exposing the response body' do
    stub_request(:post, 'https://atlas.example.test/api/v1/map-match').to_return(
      status: 422,
      body: { error: { message: 'coordinate 52.5,13.4 could not be matched' } }.to_json
    )

    expect do
      client.map_match(shape: [{ lat: 52.5, lon: 13.4 }], mode: 'auto')
    end.to raise_error(MapMatching::Atlas::Client::InvalidRequest) { |error|
      expect(error).not_to be_transient
      expect(error.message).not_to include('52.5', '13.4')
    }
  end

  it 'retains Retry-After for capacity errors' do
    stub_request(:post, 'https://atlas.example.test/api/v1/map-match')
      .to_return(status: 429, headers: { 'Retry-After' => '3' })

    expect do
      client.map_match(shape: [{ lat: 52.5, lon: 13.4 }], mode: 'auto')
    end.to raise_error(MapMatching::Atlas::Client::RateLimited) { |error|
      expect(error).to be_transient
      expect(error.retry_after).to eq(3)
    }
  end

  it 'does not follow redirects' do
    stub_request(:get, 'https://atlas.example.test/api/v1/health')
      .to_return(status: 302, headers: { 'Location' => 'https://other.example.test/' })

    expect { client.health }.to raise_error(MapMatching::Atlas::Client::ProviderError)
  end

  it 'treats malformed successful responses as retryable provider failures' do
    stub_request(:get, 'https://atlas.example.test/api/v1/health')
      .to_return(status: 200, body: '{not-json')

    expect { client.health }.to raise_error(MapMatching::Atlas::Client::MalformedResponse) { |error|
      expect(error).to be_transient
    }
  end

  it 'allows private Atlas addresses on cloud deployments and pins the resolved address' do
    allow(DawarichSettings).to receive(:self_hosted?).and_return(false)
    allow(Resolv).to receive(:getaddress).with('atlas.example.test').and_return('10.0.0.5')
    stub_request(:get, 'https://atlas.example.test/api/v1/version')
      .to_return(status: 200, body: { data: { version: '0.6.0' } }.to_json)
    expect(Net::HTTP).to receive(:new).with('atlas.example.test', 443, nil).and_call_original

    expect(client.version[:version]).to eq('0.6.0')
  end

  it 'rejects embedded credentials even for self-hosted Atlas' do
    credentialed = described_class.new(base_url: 'http://user:secret@atlas.example.test')

    expect { credentialed.health }.to raise_error(MapMatching::Atlas::Client::Error, /credentials/i)
  end
end
