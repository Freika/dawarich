# frozen_string_literal: true

require 'rails_helper'
require 'geocoder/results/photon'

RSpec.describe Places::NearbySearch do
  before do
    allow(DawarichSettings).to receive(:reverse_geocoding_enabled?).and_return(true)
  end

  let(:lat) { 52.5126 }
  let(:lon) { 13.4012 }

  let(:photon_result) do
    instance_double(
      Geocoder::Result::Photon,
      data: {
        'properties' => {
          'osm_id' => 1_234_567, 'osm_type' => 'N', 'osm_key' => 'amenity',
          'osm_value' => 'cafe', 'name' => 'Café Bravo', 'city' => 'Berlin',
          'country' => 'Germany', 'street' => 'Bergmannstraße', 'housenumber' => '1',
          'postcode' => '10961'
        },
        'geometry' => { 'coordinates' => [lon, lat], 'type' => 'Point' }
      }
    )
  end

  describe '#call' do
    it 'returns hashes with id, source, geodata keys' do
      allow(Geocoder).to receive(:search).and_return([photon_result])

      result = described_class.new(latitude: lat, longitude: lon).call

      expect(result.first).to include(
        id: nil,
        name: 'Café Bravo',
        source: 'photon',
        osm_id: 1_234_567
      )
      expect(result.first[:geodata]).to eq(photon_result.data)
    end

    it 'returns [] when reverse geocoding is disabled' do
      allow(DawarichSettings).to receive(:reverse_geocoding_enabled?).and_return(false)

      expect(described_class.new(latitude: lat, longitude: lon).call).to eq([])
    end

    it 'returns [] when coordinates are zero (degenerate visit)' do
      expect(Geocoder).not_to receive(:search)

      expect(described_class.new(latitude: 0.0, longitude: 0.0).call).to eq([])
    end

    it 'handles invalid provider requests without reporting an application exception' do
      allow(Geocoder).to receive(:search).and_raise(Geocoder::InvalidRequest)
      allow(ExceptionReporter).to receive(:call)
      allow(Rails.logger).to receive(:warn)

      expect(described_class.new(latitude: lat, longitude: lon).call).to eq([])
      expect(ExceptionReporter).not_to have_received(:call)
      expect(Rails.logger).to have_received(:warn).with(/Nearby search provider error: Geocoder::InvalidRequest/)
    end

    it 'handles transient provider outages without reporting an application exception' do
      allow(Geocoder).to receive(:search).and_raise(Geocoder::LookupTimeout.new('execution expired'))
      allow(ExceptionReporter).to receive(:call)
      allow(Rails.logger).to receive(:warn)

      expect(described_class.new(latitude: lat, longitude: lon).call).to eq([])
      expect(ExceptionReporter).not_to have_received(:call)
      expect(Rails.logger).to have_received(:warn).with(/Nearby search provider error: Geocoder::LookupTimeout/)
    end

    it 'handles a dropped TLS connection without reporting an application exception' do
      allow(Geocoder).to receive(:search).and_raise(OpenSSL::SSL::SSLError, 'unexpected eof while reading')
      allow(ExceptionReporter).to receive(:call)
      allow(Rails.logger).to receive(:warn)

      expect(described_class.new(latitude: lat, longitude: lon).call).to eq([])
      expect(ExceptionReporter).not_to have_received(:call)
      expect(Rails.logger).to have_received(:warn).with(/Nearby search provider error/)
    end

    it 'keeps the coordinates out of the handled provider error log' do
      allow(Geocoder).to receive(:search).and_raise(Geocoder::InvalidRequest)
      allow(Rails.logger).to receive(:warn)

      described_class.new(latitude: lat, longitude: lon).call

      expect(Rails.logger).to have_received(:warn).with(satisfy { |line| !line.include?('52.51') })
    end

    it 'logs a reported error so self-hosted instances are not left silent' do
      allow(DawarichSettings).to receive(:self_hosted?).and_return(true)
      allow(Geocoder).to receive(:search).and_raise(StandardError, 'photon down')
      allow(Rails.logger).to receive(:error)

      expect(described_class.new(latitude: lat, longitude: lon).call).to eq([])
      expect(Rails.logger).to have_received(:error).with(/Nearby search failed: StandardError/)
    end

    it 'reports a misconfigured provider' do
      allow(Geocoder).to receive(:search).and_raise(Geocoder::RequestDenied)
      allow(ExceptionReporter).to receive(:call)

      expect(described_class.new(latitude: lat, longitude: lon).call).to eq([])
      expect(ExceptionReporter).to have_received(:call).with(instance_of(Geocoder::RequestDenied), anything)
    end

    it 'reports a rate-limited provider' do
      allow(Geocoder).to receive(:search).and_raise(Geocoder::OverQueryLimitError)
      allow(ExceptionReporter).to receive(:call)

      expect(described_class.new(latitude: lat, longitude: lon).call).to eq([])
      expect(ExceptionReporter).to have_received(:call).with(instance_of(Geocoder::OverQueryLimitError), anything)
    end

    it 'reports unexpected errors and returns []' do
      allow(Geocoder).to receive(:search).and_raise(StandardError, 'photon down')
      allow(ExceptionReporter).to receive(:call)

      expect(described_class.new(latitude: lat, longitude: lon).call).to eq([])
      expect(ExceptionReporter).to have_received(:call)
    end

    it 'keeps the coordinates out of the exception report' do
      allow(Geocoder).to receive(:search).and_raise(StandardError, 'photon down')
      allow(ExceptionReporter).to receive(:call)

      described_class.new(latitude: lat, longitude: lon).call

      expect(ExceptionReporter).to have_received(:call) do |_error, context|
        expect(context).not_to include(lat.to_s, lon.to_s)
      end
    end

    context 'with cache: true' do
      before { Rails.cache.clear }

      it 'hits Geocoder only once for repeated calls within TTL' do
        allow(Geocoder).to receive(:search).and_return([photon_result])

        described_class.new(latitude: lat, longitude: lon, cache: true).call
        described_class.new(latitude: lat, longitude: lon, cache: true).call

        expect(Geocoder).to have_received(:search).once
      end

      it 'does not cache the empty result of a handled provider error' do
        allow(Rails.logger).to receive(:warn)
        allow(Geocoder).to receive(:search).and_raise(Geocoder::InvalidRequest)

        expect(described_class.new(latitude: lat, longitude: lon, cache: true).call).to eq([])

        allow(Geocoder).to receive(:search).and_return([photon_result])

        expect(described_class.new(latitude: lat, longitude: lon, cache: true).call.size).to eq(1)
      end

      it 'does not cache the empty result of a reported error' do
        allow(ExceptionReporter).to receive(:call)
        allow(Geocoder).to receive(:search).and_raise(StandardError, 'photon down')

        expect(described_class.new(latitude: lat, longitude: lon, cache: true).call).to eq([])

        allow(Geocoder).to receive(:search).and_return([photon_result])

        expect(described_class.new(latitude: lat, longitude: lon, cache: true).call.size).to eq(1)
      end
    end

    context 'with cache: false (default)' do
      it 'hits Geocoder on every call' do
        allow(Geocoder).to receive(:search).and_return([photon_result])

        described_class.new(latitude: lat, longitude: lon).call
        described_class.new(latitude: lat, longitude: lon).call

        expect(Geocoder).to have_received(:search).twice
      end
    end
  end
end
