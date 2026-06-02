# frozen_string_literal: true

require 'rails_helper'
require 'geocoder/results/photon'

RSpec.describe Places::Search do
  before do
    allow(DawarichSettings).to receive(:reverse_geocoding_enabled?).and_return(true)
  end

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

      results = described_class.new(query: 'Bravo', latitude: lat, longitude: lon, radius: 1.0).call

      expect(results.size).to eq(1)
      expect(results.first).to include(name: 'Café Bravo', source: 'photon')
    end

    it 'biases the Photon search to the visit coordinates' do
      expect(Geocoder).to receive(:search)
        .with('Bravo', hash_including(bias: { latitude: lat, longitude: lon }))
        .and_return([])

      described_class.new(query: 'Bravo', latitude: lat, longitude: lon, radius: 1.0).call
    end

    it 'filters out results beyond the radius' do
      near = photon(name: 'Near', plat: lat, plon: lon)
      far  = photon(name: 'Far', plat: 53.5, plon: 14.5) # ~140 km away

      allow(Geocoder).to receive(:search).and_return([near, far])

      results = described_class.new(query: 'xx', latitude: lat, longitude: lon, radius: 1.0).call

      expect(results.map { |r| r[:name] }).to eq(['Near'])
    end

    it 'orders results by distance, nearest first' do
      nearest = photon(name: 'Nearest', plat: lat, plon: lon)
      farther = photon(name: 'Farther', plat: 52.520, plon: 13.405) # ~0.9 km away

      allow(Geocoder).to receive(:search).and_return([farther, nearest])

      results = described_class.new(query: 'xx', latitude: lat, longitude: lon, radius: 5.0).call

      expect(results.map { |r| r[:name] }).to eq(%w[Nearest Farther])
    end

    it 'returns [] for a query shorter than 2 chars' do
      expect(Geocoder).not_to receive(:search)
      expect(described_class.new(query: 'a', latitude: lat, longitude: lon, radius: 1.0).call).to eq([])
    end

    it 'returns [] when reverse geocoding is disabled' do
      allow(DawarichSettings).to receive(:reverse_geocoding_enabled?).and_return(false)
      expect(described_class.new(query: 'cafe', latitude: lat, longitude: lon, radius: 1.0).call).to eq([])
    end

    it 'rescues Geocoder errors and returns []' do
      allow(Geocoder).to receive(:search).and_raise(StandardError, 'photon down')
      expect(ExceptionReporter).to receive(:call).with(instance_of(StandardError), anything)
      expect(described_class.new(query: 'cafe', latitude: lat, longitude: lon, radius: 1.0).call).to eq([])
    end
  end
end
