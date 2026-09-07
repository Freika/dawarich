# frozen_string_literal: true

require 'rails_helper'

# Regression spec for the Photon/Geoapify single-Feature passthrough.
#
# Stored `Point#geodata` for the Photon and Geoapify providers is a single
# GeoJSON Feature (not a FeatureCollection) whose `properties` carries
# `osm_value` (Photon) or `result_type` (Geoapify) and never contains a
# top-level `'type'` key. The existing `suggester_spec.rb` "Photon format"
# context uses a synthetic `properties['type']`, which masks regressions in
# the real provider-key lookup. These specs drive the
# `elsif geodata['type'] == 'Feature'` passthrough with realistic provider
# property shapes so a revert to `properties['type']` grouping is caught.
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
end
