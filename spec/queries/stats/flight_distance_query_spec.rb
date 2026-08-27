# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Stats::FlightDistanceQuery do
  let(:user) { create(:user) }

  subject(:flight_meters) { described_class.new(user, 2026, 4).call }

  context 'without any flights' do
    it 'returns zero' do
      expect(flight_meters).to eq(0)
    end
  end

  context 'with flights dated inside the month' do
    before do
      create(:flight, user: user, flight_date: Date.new(2026, 4, 3), distance_km: 633.4)
      create(:flight, user: user, flight_date: Date.new(2026, 4, 28), distance_km: 120.6)
    end

    it 'sums their distance in meters' do
      expect(flight_meters).to eq(754_000)
    end
  end

  context 'with flights dated outside the month' do
    before do
      create(:flight, user: user, flight_date: Date.new(2026, 3, 31), distance_km: 500.0)
      create(:flight, user: user, flight_date: Date.new(2026, 5, 1), distance_km: 500.0)
    end

    it 'excludes them' do
      expect(flight_meters).to eq(0)
    end
  end

  context 'with a flight belonging to another user' do
    before do
      create(:flight, user: create(:user), flight_date: Date.new(2026, 4, 10), distance_km: 900.0)
    end

    it 'does not borrow it' do
      expect(flight_meters).to eq(0)
    end
  end

  context 'with a flight whose distance is unknown' do
    before { create(:flight, user: user, flight_date: Date.new(2026, 4, 10), distance_km: nil) }

    it 'skips it instead of failing' do
      expect(flight_meters).to eq(0)
    end
  end

  context 'with a dateless flight that departs in the new month only in the user timezone' do
    let(:user) { create(:user, settings: { 'timezone' => 'Europe/Berlin' }) }

    before do
      create(:flight, user: user, flight_date: nil,
                      departure_time: Time.utc(2026, 3, 31, 23, 0), distance_km: 300.0)
    end

    it 'counts it, because locally it departed on April 1st' do
      expect(flight_meters).to eq(300_000)
    end
  end

  context 'with a dateless flight that departs in the previous month only in the user timezone' do
    let(:user) { create(:user, settings: { 'timezone' => 'America/Los_Angeles' }) }

    before do
      create(:flight, user: user, flight_date: nil,
                      departure_time: Time.utc(2026, 4, 1, 3, 0), distance_km: 300.0)
    end

    it 'excludes it, because locally it departed on March 31st' do
      expect(flight_meters).to eq(0)
    end
  end

  context 'with a flight that has neither a date nor a departure time' do
    before do
      create(:flight, user: user, flight_date: nil, departure_time: nil,
                      arrival_time: nil, distance_km: 300.0)
    end

    it 'skips it instead of failing' do
      expect(flight_meters).to eq(0)
    end
  end
end
