# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Api::FlightSerializer do
  it 'produces a GeoJSON LineString feature' do
    flight = build(:flight)
    feature = described_class.new(flight).call

    expect(feature[:type]).to eq('Feature')
    expect(feature[:geometry][:type]).to eq('LineString')
    expect(feature[:geometry][:coordinates]).to eq([[13.493, 52.351], [2.547, 49.009]])
    expect(feature[:properties][:from_code]).to eq('EDDB')
    expect(feature[:properties][:airline_name]).to eq('Air France')
  end

  it 'returns the stored AirTrail track instead of the airport pair' do
    track = [[13.493, 52.351], [8.0, 51.0], [2.547, 49.009]]
    flight = build(:flight, track_coordinates: track)

    expect(described_class.new(flight).call[:geometry][:coordinates]).to eq(track)
  end
end
