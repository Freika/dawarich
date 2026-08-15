# frozen_string_literal: true

require 'rails_helper'

RSpec.describe AirTrail::ImportFlights do
  let(:user) do
    create(:user).tap do |u|
      u.update!(settings: u.settings.merge('airtrail_url' => 'https://a.example',
                                           'airtrail_api_key' => 'k'))
    end
  end

  def airtrail_flight(id:, dep: '2026-04-20T10:00:00.000+00:00', arr: '2026-04-20T12:00:00.000+00:00')
    {
      'id' => id, 'date' => '2026-04-20', 'datePrecision' => 'day',
      'departure' => dep, 'arrival' => arr, 'flightNumber' => 'AF1235',
      'aircraftReg' => 'F-GKXA', 'note' => nil, 'duration' => 7200,
      'from' => { 'icao' => 'EDDB', 'iata' => 'BER', 'lat' => 52.351, 'lon' => 13.493, 'name' => 'Berlin' },
      'to' => { 'icao' => 'LFPG', 'iata' => 'CDG', 'lat' => 49.009, 'lon' => 2.547, 'name' => 'Paris' },
      'airline' => { 'name' => 'Air France', 'iata' => 'AF' },
      'aircraft' => { 'name' => 'A320' },
      'seats' => [{ 'seat' => 'window', 'seatNumber' => '14A', 'seatClass' => 'economy' }]
    }
  end

  it 'creates flights from the AirTrail payload' do
    allow_any_instance_of(AirTrail::Client).to receive(:flights).and_return([airtrail_flight(id: 1)])

    result = described_class.new(user).call

    expect(user.flights.count).to eq(1)
    flight = user.flights.first
    expect(flight.external_id).to eq(1)
    expect(flight.from_code).to eq('EDDB')
    expect(flight.to_lat).to eq(49.009)
    expect(flight.airline_iata).to eq('AF')
    expect(flight.seat_class).to eq('economy')
    expect(flight.distance_km).to be_within(10).of(855)
    expect(result[:created]).to eq(1)
  end

  it 'updates an existing flight by external_id' do
    create(:flight, user: user, external_id: 1, flight_number: 'OLD')
    allow_any_instance_of(AirTrail::Client).to receive(:flights).and_return([airtrail_flight(id: 1)])

    described_class.new(user).call

    expect(user.flights.count).to eq(1)
    expect(user.flights.first.flight_number).to eq('AF1235')
  end

  it 'deletes local flights absent from AirTrail' do
    create(:flight, user: user, external_id: 99)
    allow_any_instance_of(AirTrail::Client).to receive(:flights).and_return([airtrail_flight(id: 1)])

    result = described_class.new(user).call

    expect(user.flights.pluck(:external_id)).to eq([1])
    expect(result[:deleted]).to eq(1)
  end

  it 'no-ops when settings are blank' do
    user.update!(settings: user.settings.merge('airtrail_url' => nil, 'airtrail_api_key' => nil))
    expect(described_class.new(user).call).to include(skipped: true)
  end

  it 'records last synced at' do
    allow_any_instance_of(AirTrail::Client).to receive(:flights).and_return([])
    described_class.new(user).call
    expect(user.reload.settings['airtrail_last_synced_at']).to be_present
  end

  it 'continues the import when a concurrent sync inserts the same flight first' do
    allow_any_instance_of(AirTrail::Client).to receive(:flights)
      .and_return([airtrail_flight(id: 1), airtrail_flight(id: 2)])

    raised = false
    allow_any_instance_of(Flight).to receive(:update!).and_wrap_original do |original, *args|
      if original.receiver.external_id == 1 && !raised
        raised = true
        raise ActiveRecord::RecordNotUnique, 'duplicate key value violates unique constraint'
      end
      original.call(*args)
    end

    result = described_class.new(user).call

    expect(user.flights.pluck(:external_id)).to contain_exactly(2)
    expect(result[:created]).to eq(1)
  end

  it 'does not clobber settings keys written while syncing' do
    allow_any_instance_of(AirTrail::Client).to receive(:flights).and_return([])
    service = described_class.new(user)
    User.find(user.id).tap { |u| u.update!(settings: u.settings.merge('other_key' => 'x')) }

    service.call

    expect(user.reload.settings['other_key']).to eq('x')
    expect(user.settings['airtrail_last_synced_at']).to be_present
  end
end
