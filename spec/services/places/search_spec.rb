# frozen_string_literal: true

require 'rails_helper'
require 'geocoder/results/photon'

RSpec.describe Places::Search do
  before do
    allow(DawarichSettings).to receive(:reverse_geocoding_enabled?).and_return(true)
  end

  let(:user) { create(:user) }
  let(:lat) { 52.5126 }
  let(:lon) { 13.4012 }

  def photon(name:, plat:, plon:)
    instance_double(
      Geocoder::Result::Photon,
      data: {
        'properties' => { 'name' => name, 'osm_id' => name.hash.abs },
        'geometry' => { 'coordinates' => [plon, plat], 'type' => 'Point' }
      }
    )
  end

  describe '#call' do
    it 'returns nearby matches in the select_place shape' do
      allow(Geocoder).to receive(:search).and_return([photon(name: 'Café Bravo', plat: lat, plon: lon)])

      results = described_class.new(user: user, query: 'Bravo', latitude: lat, longitude: lon, radius: 1.0).call

      expect(results.size).to eq(1)
      expect(results.first).to include(name: 'Café Bravo', source: 'photon')
    end

    it 'biases the Photon search to the visit coordinates' do
      expect(Geocoder).to receive(:search)
        .with('Bravo', hash_including(bias: { latitude: lat, longitude: lon }))
        .and_return([])

      described_class.new(user: user, query: 'Bravo', latitude: lat, longitude: lon, radius: 1.0).call
    end

    it 'filters out results beyond the radius' do
      near = photon(name: 'Near', plat: lat, plon: lon)
      far  = photon(name: 'Far', plat: 53.5, plon: 14.5) # ~140 km away

      allow(Geocoder).to receive(:search).and_return([near, far])

      results = described_class.new(user: user, query: 'xx', latitude: lat, longitude: lon, radius: 1.0).call

      expect(results.map { |r| r[:name] }).to eq(['Near'])
    end

    it 'orders results by distance, nearest first' do
      nearest = photon(name: 'Nearest', plat: lat, plon: lon)
      farther = photon(name: 'Farther', plat: 52.520, plon: 13.405) # ~0.9 km away

      allow(Geocoder).to receive(:search).and_return([farther, nearest])

      results = described_class.new(user: user, query: 'xx', latitude: lat, longitude: lon, radius: 5.0).call

      expect(results.map { |r| r[:name] }).to eq(%w[Nearest Farther])
    end

    it 'returns [] for a query shorter than 2 chars' do
      expect(Geocoder).not_to receive(:search)
      expect(described_class.new(user: user, query: 'a', latitude: lat, longitude: lon, radius: 1.0).call).to eq([])
    end

    it 'returns [] when reverse geocoding is disabled' do
      allow(DawarichSettings).to receive(:reverse_geocoding_enabled?).and_return(false)
      expect(described_class.new(user: user, query: 'cafe', latitude: lat, longitude: lon, radius: 1.0).call).to eq([])
    end

    it 'handles invalid provider requests without reporting an application exception' do
      allow(Geocoder).to receive(:search).and_raise(Geocoder::InvalidRequest)
      allow(ExceptionReporter).to receive(:call)
      allow(Rails.logger).to receive(:warn)

      expect(described_class.new(user: user, query: 'cafe', latitude: lat, longitude: lon, radius: 1.0).call).to eq([])
      expect(ExceptionReporter).not_to have_received(:call)
      expect(Rails.logger).to have_received(:warn).with(/Place search provider error: Geocoder::InvalidRequest/)
    end

    it 'keeps the search text out of the handled provider error log' do
      allow(Geocoder).to receive(:search).and_raise(Geocoder::InvalidRequest)
      allow(Rails.logger).to receive(:warn)

      described_class.new(user: user, query: 'Bergmannstraße 1', latitude: lat, longitude: lon, radius: 1.0).call

      expect(Rails.logger).to have_received(:warn).with(satisfy { |line| !line.include?('Bergmannstraße') })
    end

    it 'handles transient provider outages without reporting an application exception' do
      allow(Geocoder).to receive(:search).and_raise(Geocoder::LookupTimeout.new('execution expired'))
      allow(ExceptionReporter).to receive(:call)
      allow(Rails.logger).to receive(:warn)

      expect(described_class.new(user: user, query: 'cafe', latitude: lat, longitude: lon, radius: 1.0).call).to eq([])
      expect(ExceptionReporter).not_to have_received(:call)
      expect(Rails.logger).to have_received(:warn).with(/Place search provider error: Geocoder::LookupTimeout/)
    end

    it 'handles a dropped TLS connection without reporting an application exception' do
      allow(Geocoder).to receive(:search).and_raise(OpenSSL::SSL::SSLError, 'unexpected eof while reading')
      allow(ExceptionReporter).to receive(:call)
      allow(Rails.logger).to receive(:warn)

      expect(described_class.new(user: user, query: 'cafe', latitude: lat, longitude: lon, radius: 1.0).call).to eq([])
      expect(ExceptionReporter).not_to have_received(:call)
      expect(Rails.logger).to have_received(:warn).with(/Place search provider error/)
    end

    it 'logs a reported error so self-hosted instances are not left silent' do
      allow(DawarichSettings).to receive(:self_hosted?).and_return(true)
      allow(Geocoder).to receive(:search).and_raise(StandardError, 'photon down')
      allow(Rails.logger).to receive(:error)

      expect(described_class.new(user: user, query: 'cafe', latitude: lat, longitude: lon, radius: 1.0).call).to eq([])
      expect(Rails.logger).to have_received(:error).with(/Place search failed: StandardError/)
    end

    it 'reports a misconfigured provider' do
      allow(Geocoder).to receive(:search).and_raise(Geocoder::RequestDenied)
      allow(ExceptionReporter).to receive(:call)

      expect(described_class.new(user: user, query: 'cafe', latitude: lat, longitude: lon, radius: 1.0).call).to eq([])
      expect(ExceptionReporter).to have_received(:call).with(instance_of(Geocoder::RequestDenied), anything)
    end

    it 'reports a rate-limited provider' do
      allow(Geocoder).to receive(:search).and_raise(Geocoder::OverQueryLimitError)
      allow(ExceptionReporter).to receive(:call)

      expect(described_class.new(user: user, query: 'cafe', latitude: lat, longitude: lon, radius: 1.0).call).to eq([])
      expect(ExceptionReporter).to have_received(:call).with(instance_of(Geocoder::OverQueryLimitError), anything)
    end

    it 'reports unexpected errors and returns []' do
      allow(Geocoder).to receive(:search).and_raise(StandardError, 'photon down')
      expect(ExceptionReporter).to receive(:call).with(instance_of(StandardError), anything)
      expect(described_class.new(user: user, query: 'cafe', latitude: lat, longitude: lon, radius: 1.0).call).to eq([])
    end

    it 'keeps the query and coordinates out of the exception report' do
      allow(Geocoder).to receive(:search).and_raise(StandardError, 'photon down')
      allow(ExceptionReporter).to receive(:call)

      described_class.new(user: user, query: 'cafe', latitude: lat, longitude: lon, radius: 1.0).call

      expect(ExceptionReporter).to have_received(:call) do |_error, context|
        expect(context).not_to include('cafe', lat.to_s, lon.to_s)
      end
    end
  end

  describe 'user mode (no ENV)' do
    before do
      allow(DawarichSettings).to receive(:reverse_geocoding_enabled?).and_return(false)
      allow(Geocoder).to receive(:search).and_call_original
      allow_any_instance_of(Geocoder::Lookup::Base).to receive(:cache).and_return(nil)
    end

    it 'routes forward search through the user provider' do
      create(:service_setting, :active, user: user, config: { 'host' => 'photon.mine.example.com' })
      stub_request(:get, %r{https://photon\.mine\.example\.com/api})
        .to_return(status: 200, body: { type: 'FeatureCollection', features: [] }.to_json,
                   headers: { 'Content-Type' => 'application/json' })

      described_class.new(user: user, query: 'cafe', latitude: lat, longitude: lon, radius: 1.0).call

      expect(WebMock).to have_requested(:get, %r{https://photon\.mine\.example\.com/api})
    end

    it 'returns an empty list for an unconfigured user without HTTP' do
      result = described_class.new(user: user, query: 'cafe', latitude: lat, longitude: lon, radius: 1.0).call

      expect(result).to eq([])
      expect(WebMock).not_to have_requested(:get, /.*/)
    end
  end
end
