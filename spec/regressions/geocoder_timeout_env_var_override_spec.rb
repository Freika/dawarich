# frozen_string_literal: true

require 'rails_helper'
require 'webrick'

RSpec.describe 'Geocoder timeout with real loopback fake geocoder server' do
  let(:user) { create(:user) }
  let(:lat) { 52.5126 }
  let(:lon) { 13.4012 }

  # Helper method to spin up a real in-process HTTP fake geocoder server on an ephemeral port
  # with an explicit response delay configured for the test.
  def with_fake_geocoder(response_delay: 0)
    server = WEBrick::HTTPServer.new(
      BindAddress: '127.0.0.1',
      Port: 0,
      Logger: WEBrick::Log.new(File::NULL),
      AccessLog: []
    )
    port = server.config[:Port]

    server.mount_proc '/api' do |_req, res|
      sleep(response_delay) if response_delay.positive?
      res.status = 200
      res['Content-Type'] = 'application/json'
      res.body = {
        type: 'FeatureCollection',
        features: [
          {
            type: 'Feature',
            geometry: { type: 'Point', coordinates: [13.4012, 52.5126] },
            properties: { name: 'Test Place', osm_id: 99999 }
          }
        ]
      }.to_json
    end

    server.mount_proc '/reverse' do |_req, res|
      sleep(response_delay) if response_delay.positive?
      res.status = 200
      res['Content-Type'] = 'application/json'
      res.body = {
        type: 'FeatureCollection',
        features: [
          {
            type: 'Feature',
            geometry: { type: 'Point', coordinates: [13.4012, 52.5126] },
            properties: { name: 'Reverse Test Place', osm_id: 88888 }
          }
        ]
      }.to_json
    end

    thread = Thread.new { server.start }
    yield port
  ensure
    server&.shutdown
    thread&.join(2)
  end

  around do |example|
    WebMock.disable_net_connect!(allow_localhost: true)
    original_config = Geocoder.config.to_hash.dup
    example.run
  ensure
    Geocoder::Configuration.instance.data = original_config
    WebMock.disable_net_connect!(allow_localhost: false)
  end

  before do
    allow(DawarichSettings).to receive(:reverse_geocoding_enabled?).and_return(true)
    allow(Geocoder).to receive(:search).and_call_original
    allow(ExceptionReporter).to receive(:call)
    allow(Rails.logger).to receive(:warn)
  end

  describe 'Real HTTP socket timeout vs successful response against fake geocoder' do
    it 'times out with Geocoder::LookupTimeout when fake server latency exceeds the configured timeout' do
      with_fake_geocoder(response_delay: 0.4) do |port|
        Geocoder.configure(
          lookup: :photon,
          photon: { host: "127.0.0.1:#{port}" },
          use_https: false,
          timeout: 0.1,
          cache: nil
        )

        expect do
          Geocoder.search('Berlin')
        end.to raise_error(Geocoder::LookupTimeout)
      end
    end

    it 'successfully receives and parses GeoJSON when fake server latency is within the configured timeout' do
      with_fake_geocoder(response_delay: 0.05) do |port|
        Geocoder.configure(
          lookup: :photon,
          photon: { host: "127.0.0.1:#{port}" },
          use_https: false,
          timeout: 2.0,
          cache: nil
        )

        results = Geocoder.search('Berlin')

        expect(results).not_to be_empty
        expect(results.first.data.dig('properties', 'name')).to eq('Test Place')
      end
    end

    it 'gracefully catches real HTTP socket timeout in Places::Search without raising uncaught errors' do
      with_fake_geocoder(response_delay: 0.4) do |port|
        Geocoder.configure(
          lookup: :photon,
          photon: { host: "127.0.0.1:#{port}" },
          use_https: false,
          timeout: 0.1,
          cache: nil
        )

        results = Places::Search.new(user: user, query: 'Test Place', latitude: lat, longitude: lon, radius: 5.0).call

        expect(results).to eq([])
        expect(ExceptionReporter).not_to have_received(:call)
      end
    end

    it 'gracefully catches real HTTP socket timeout in Places::NearbySearch without raising uncaught errors' do
      with_fake_geocoder(response_delay: 0.4) do |port|
        Geocoder.configure(
          lookup: :photon,
          photon: { host: "127.0.0.1:#{port}" },
          use_https: false,
          timeout: 0.1,
          cache: nil
        )

        results = Places::NearbySearch.new(user: user, latitude: lat, longitude: lon).call

        expect(results).to eq([])
        expect(ExceptionReporter).not_to have_received(:call)
      end
    end
  end
end
