# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Trips::Countries do
  let(:trip) { instance_double('Trip') }
  let(:point1) { instance_double('Point', lonlat: factory.point(10.0, 50.0)) }
  let(:point2) { instance_double('Point', lonlat: factory.point(20.0, 60.0)) }
  let(:point3) { instance_double('Point', lonlat: factory.point(30.0, 70.0)) }
  let(:point4) { instance_double('Point', lonlat: nil) }
  let(:factory) { RGeo::Geographic.spherical_factory }
  let(:points) { [point1, point2, point3, point4] }

  let(:geo_json_content) do
    {
      type: 'FeatureCollection',
      features: [
        {
          type: 'Feature',
          properties: { ADMIN: 'Germany', ISO_A3: 'DEU', ISO_A2: 'DE' },
          geometry: { type: 'MultiPolygon', coordinates: [] }
        }
      ]
    }.to_json
  end

  before do
    allow(trip).to receive(:points).and_return(points)
    allow(File).to receive(:read).with(Trips::Countries::FILE_PATH).and_return(geo_json_content)

    # Explicitly stub all Geocoder calls with specific coordinates
    stub_request(:get, 'https://photon.dawarich.app/reverse?lang=en&lat=50.0&limit=1&lon=10.0')
      .to_return(
        status: 200,
        body: {
          type: 'FeatureCollection',
          features: [{ type: 'Feature', properties: { countrycode: 'DE' } }]
        }.to_json
      )

    stub_request(:get, 'https://photon.dawarich.app/reverse?lang=en&lat=60.0&limit=1&lon=20.0')
      .to_return(
        status: 200,
        body: {
          type: 'FeatureCollection',
          features: [{ type: 'Feature', properties: { countrycode: 'SE' } }]
        }.to_json
      )

    stub_request(:get, 'https://photon.dawarich.app/reverse?lang=en&lat=70.0&limit=1&lon=30.0')
      .to_return(
        status: 200,
        body: {
          type: 'FeatureCollection',
          features: [{ type: 'Feature', properties: { countrycode: 'FI' } }]
        }.to_json
      )

    allow(Rails.logger).to receive(:info)
    allow(Rails.logger).to receive(:error)
  end

  describe '#call' do
    it 'returns a hash with country counts' do
      allow(Thread).to receive(:new).and_yield

      result = described_class.new(trip).call

      expect(result).to be_a(Hash)
      expect(result.keys).to match_array(%w[DE SE FI])
      expect(result.values.sum).to eq(3)
    end

    it 'handles points without coordinates' do
      allow(Thread).to receive(:new).and_yield

      result = described_class.new(trip).call

      expect(result.values.sum).to eq(3) # Should only count the 3 valid points
    end

    it 'processes batches in multiple threads' do
      expect(Thread).to receive(:new).at_least(:twice).and_yield

      described_class.new(trip).call
    end

    it 'sorts countries by count in descending order' do
      allow(Thread).to receive(:new).and_yield
      allow(points).to receive(:to_a).and_return([point1, point1, point2, point3, point4])

      # Make sure we have a stub for the duplicated point
      stub_request(:get, 'https://photon.dawarich.app/reverse?lang=en&lat=50.0&limit=1&lon=10.0')
        .to_return(
          status: 200,
          body: {
            type: 'FeatureCollection',
            features: [{ type: 'Feature', properties: { countrycode: 'DE' } }]
          }.to_json
        )

      result = described_class.new(trip).call

      expect(result.keys.first).to eq('DE')
      expect(result['DE']).to eq(2)
    end
  end
end
