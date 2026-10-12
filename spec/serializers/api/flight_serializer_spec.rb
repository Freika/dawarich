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
end
