# frozen_string_literal: true

require 'rails_helper'

RSpec.describe AirTrail::FlightMapper do
  def payload(overrides = {})
    {
      'id' => 8, 'date' => '2026-04-20', 'datePrecision' => 'day',
      'departure' => nil, 'arrival' => nil,
      'departureScheduled' => '2026-04-20T10:00:00.000+00:00',
      'arrivalScheduled' => '2026-04-20T12:00:00.000+00:00',
      'flightNumber' => 'AF1235',
      'from' => { 'icao' => 'EDDB', 'lat' => 52.351, 'lon' => 13.493, 'name' => 'Berlin' },
      'to' => { 'icao' => 'LFPG', 'lat' => 49.009, 'lon' => 2.547, 'name' => 'Paris' }
    }.merge(overrides)
  end

  it 'uses the departure and arrival times AirTrail reports as actual' do
    attributes = described_class.new(
      payload('departure' => '2026-04-20T10:30:00.000+00:00', 'arrival' => '2026-04-20T12:15:00.000+00:00')
    ).attributes

    expect(attributes[:departure_time]).to eq(Time.utc(2026, 4, 20, 10, 30))
    expect(attributes[:arrival_time]).to eq(Time.utc(2026, 4, 20, 12, 15))
  end

  it 'falls back to the scheduled times when a flight has no actual times yet' do
    attributes = described_class.new(payload).attributes

    expect(attributes[:departure_time]).to eq(Time.utc(2026, 4, 20, 10, 0))
    expect(attributes[:arrival_time]).to eq(Time.utc(2026, 4, 20, 12, 0))
  end

  it 'prefers actual takeoff and landing times over the scheduled ones' do
    attributes = described_class.new(
      payload('takeoffActual' => '2026-04-20T10:40:00.000+00:00',
              'landingActual' => '2026-04-20T12:20:00.000+00:00')
    ).attributes

    expect(attributes[:departure_time]).to eq(Time.utc(2026, 4, 20, 10, 40))
    expect(attributes[:arrival_time]).to eq(Time.utc(2026, 4, 20, 12, 20))
  end

  it 'leaves the times empty when AirTrail has none for the flight' do
    attributes = described_class.new(payload('departureScheduled' => nil, 'arrivalScheduled' => nil)).attributes

    expect(attributes[:departure_time]).to be_nil
    expect(attributes[:arrival_time]).to be_nil
  end
end
