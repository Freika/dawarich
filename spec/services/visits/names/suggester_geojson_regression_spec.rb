# frozen_string_literal: true

require 'rails_helper'

# Regression spec for the Photon/Geoapify single-Feature passthrough.
#
# Stored `Point#geodata` for the Photon and Geoapify providers is a single
# GeoJSON Feature (not a FeatureCollection). Photon carries a place-rank
# `type` (house, street, ...) plus `osm_key`/`osm_value`; Geoapify carries
# `result_type` and no `type` at all, so grouping on `properties['type']`
# alone never produced a vote for Geoapify. These specs drive the
# `elsif geodata['type'] == 'Feature'` passthrough with realistic provider
# property shapes, and pin that a street or district majority never wins
# the name vote.
RSpec.describe Visits::Names::Suggester do
  subject(:suggester) { described_class.new(points) }

  describe '#call with real Photon-shape per-point geodata' do
    let(:points) do
      Array.new(3) do
        double('Point', geodata: {
                 'type' => 'Feature',
                 'geometry' => { 'type' => 'Point', 'coordinates' => [37.6177, 55.7558] },
                 'properties' => {
                   'osm_id' => 1,
                   'osm_type' => 'N',
                   'osm_key' => 'amenity',
                   'osm_value' => 'cafe',
                   'type' => 'house',
                   'name' => 'Coffee House',
                   'street' => 'Main Street',
                   'city' => 'Moscow',
                   'country' => 'Russia'
                 }
               })
      end
    end

    it 'votes the venue name across the stored points' do
      expect(suggester.call).to eq('Coffee House, Main Street, Moscow')
    end
  end

  describe '#call with real Geoapify-shape per-point geodata' do
    let(:points) do
      Array.new(3) do
        double('Point', geodata: {
                 'type' => 'Feature',
                 'geometry' => { 'type' => 'Point', 'coordinates' => [-73.993368, 40.750487] },
                 'properties' => {
                   'housenumber' => '4',
                   'street' => 'Pennsylvania Plaza',
                   'country' => 'United States',
                   'city' => 'New York',
                   'state' => 'New York',
                   'lon' => -73.993368,
                   'lat' => 40.750487,
                   'result_type' => 'building',
                   'name' => 'Madison Square Garden'
                 }
               })
      end
    end

    it 'votes the venue name across the stored points' do
      expect(suggester.call).to eq('Madison Square Garden, Pennsylvania Plaza, New York')
    end
  end

  describe '#call when the majority of points resolve to a street' do
    let(:photon_street) do
      double('Point', geodata: {
               'type' => 'Feature',
               'geometry' => { 'type' => 'Point', 'coordinates' => [12.3731, 51.3397] },
               'properties' => {
                 'osm_id' => 2, 'osm_type' => 'W', 'osm_key' => 'highway', 'osm_value' => 'residential',
                 'type' => 'street', 'name' => 'Thomaskirchhof', 'city' => 'Leipzig', 'country' => 'Germany'
               }
             })
    end
    let(:geoapify_street) do
      double('Point', geodata: {
               'type' => 'Feature',
               'geometry' => { 'type' => 'Point', 'coordinates' => [12.3731, 51.3397] },
               'properties' => {
                 'result_type' => 'street', 'name' => 'Thomaskirchhof', 'street' => 'Thomaskirchhof',
                 'city' => 'Leipzig', 'country' => 'Germany'
               }
             })
    end

    it 'does not mint a Photon street name as a venue' do
      expect(described_class.new(Array.new(3) { photon_street }).call).to be_nil
    end

    it 'does not mint a Geoapify street name as a venue' do
      expect(described_class.new(Array.new(3) { geoapify_street }).call).to be_nil
    end
  end

  describe '#call when a provider key is present but blank' do
    let(:points) do
      Array.new(3) do
        double('Point', geodata: {
                 'type' => 'Feature',
                 'geometry' => { 'type' => 'Point', 'coordinates' => [37.6177, 55.7558] },
                 'properties' => {
                   'type' => nil, 'osm_key' => 'amenity', 'osm_value' => 'cafe',
                   'name' => 'Coffee House', 'street' => 'Main Street', 'city' => 'Moscow'
                 }
               })
      end
    end

    it 'falls through to the next key instead of grouping under nil' do
      expect(suggester.call).to eq('Coffee House, Main Street, Moscow')
    end
  end
end
