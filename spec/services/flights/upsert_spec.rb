# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Flights::Upsert do
  let(:user) { create(:user) }

  def flight_attrs(id:, flight_number: 'AF1235')
    AirTrail::FlightMapper.new(
      {
        'id' => id, 'date' => '2026-04-20', 'datePrecision' => 'day',
        'departure' => '2026-04-20T10:00:00.000+00:00',
        'arrival' => '2026-04-20T12:00:00.000+00:00',
        'flightNumber' => flight_number,
        'from' => { 'icao' => 'EDDB', 'lat' => 52.351, 'lon' => 13.493, 'name' => 'Berlin' },
        'to' => { 'icao' => 'LFPG', 'lat' => 49.009, 'lon' => 2.547, 'name' => 'Paris' },
        'airline' => { 'name' => 'Air France', 'iata' => 'AF' },
        'aircraft' => { 'name' => 'A320' },
        'seats' => [{ 'seatNumber' => '14A', 'seatClass' => 'economy' }]
      }
    ).attributes
  end

  describe 'merge mode' do
    it 'creates flights without deleting existing ones' do
      create(:flight, user: user, external_id: 99)

      result = described_class.new(user, [flight_attrs(id: 1)], mode: :merge).call

      expect(user.flights.pluck(:external_id)).to contain_exactly(99, 1)
      expect(result).to include(created: 1, updated: 0, deleted: 0)
    end

    it 'updates an existing flight by external_id' do
      create(:flight, user: user, external_id: 1, flight_number: 'OLD')

      result = described_class.new(user, [flight_attrs(id: 1)], mode: :merge).call

      expect(user.flights.count).to eq(1)
      expect(user.flights.first.flight_number).to eq('AF1235')
      expect(result).to include(created: 0, updated: 1, deleted: 0)
    end
  end

  describe 'replace mode' do
    it 'deletes local flights absent from the payload' do
      create(:flight, user: user, external_id: 99)

      result = described_class.new(user, [flight_attrs(id: 1)], mode: :replace).call

      expect(user.flights.pluck(:external_id)).to eq([1])
      expect(result[:deleted]).to eq(1)
    end
  end
end
