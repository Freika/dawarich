# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Transportation features with numeric altitude' do
  it 'extracts movement features and recalculates tracks without altitude_decimal' do
    track = create(:track)
    connection = Point.connection
    connection.remove_column(:points, :altitude_decimal)
    connection.change_column(:points, :altitude, :decimal, precision: 10, scale: 2)
    Point.reset_column_information
    allow(Point).to receive(:altitude_decimal_supported?).and_return(false)

    [12.25, 17.75].each_with_index do |altitude, index|
      create(:point, user: track.user, track: track, altitude: altitude,
                     timestamp: 1_000 + index * 10, lonlat: "POINT(12.#{index} 51.0)")
    end

    features = TransportationModes::FeatureExtractor.call(track.id)
    expect(features.pluck(:altitude_m)).to eq([12.25, 17.75])
    expect(features.pluck(:dt)).to eq([nil, 10])
    expect { Tracks::Recalculator.call(track, broadcast: false) }.not_to raise_error
    expect(track.reload.duration).to eq(10)
  ensure
    Point.reset_column_information
  end
end
