# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Flights::Parsers::AirTrailJson do
  def export_flight(overrides = {})
    {
      'date' => '2026-04-20',
      'from' => { 'icao' => 'EDDB', 'lat' => 52.351, 'lon' => 13.493, 'name' => 'Berlin' },
      'to' => { 'icao' => 'LFPG', 'lat' => 49.009, 'lon' => 2.547, 'name' => 'Paris' },
      'departure' => '2026-04-20T10:00:00.000+00:00',
      'arrival' => '2026-04-20T12:00:00.000+00:00',
      'flightNumber' => 'AF1235',
      'airline' => { 'name' => 'Air France', 'iata' => 'AF' }
    }.merge(overrides)
  end

  it 'exposes format metadata' do
    expect(described_class.key).to eq(:airtrail_json)
    expect(described_class.label).to include('AirTrail')
    expect(described_class.extensions).to include('.json')
  end

  it 'unwraps a v3 export wrapper into Flight attributes' do
    data = { 'users' => [], 'flights' => [export_flight] }

    flights = described_class.call(data)

    expect(flights.size).to eq(1)
    expect(flights.first[:from_code]).to eq('EDDB')
    expect(flights.first[:flight_number]).to eq('AF1235')
  end

  it 'accepts a bare flights array' do
    flights = described_class.call([export_flight])

    expect(flights.size).to eq(1)
    expect(flights.first[:to_code]).to eq('LFPG')
  end

  it 'assigns a stable synthetic external_id when missing' do
    flights = described_class.call({ 'flights' => [export_flight] })

    id1 = flights.first[:external_id]
    id2 = described_class.call({ 'flights' => [export_flight] }).first[:external_id]

    expect(id1).to be_a(Integer)
    expect(id1).to eq(id2)
    expect(id1).to be >= Flights::ExternalId::FILE_ID_OFFSET
  end

  it 'preserves an existing AirTrail id as external_id' do
    flights = described_class.call({ 'flights' => [export_flight('id' => 42)] })

    expect(flights.first[:external_id]).to eq(42)
  end

  it 'raises when no flights are present' do
    expect { described_class.call({ 'flights' => [] }) }
      .to raise_error(Flights::Parsers::Error, /No flights found/)
  end
end
