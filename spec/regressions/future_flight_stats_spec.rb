# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Flight stats dates' do
  include ActiveSupport::Testing::TimeHelpers

  let(:user) { create(:user, settings: { 'timezone' => 'America/Los_Angeles' }) }

  it 'waits until the local flight date before creating stats or counting distance' do
    travel_to Time.utc(2026, 12, 1) do
      create(:flight, user: user, flight_date: Date.new(2027, 1, 1),
                      departure_time: Time.utc(2027, 1, 1, 3), arrival_time: Time.utc(2027, 1, 1, 5))
      Stats::CalculateMonth.new(user.id, 2027, 1).call
      expect(user.stats.where(year: 2027, month: 1)).not_to exist
      expect(user.flights.stat_months(user.timezone_iana)).to be_empty
      expect(Stats::FlightDistanceQuery.new(user, 2026, 12).call).to eq(0)
    end
    travel_to Time.utc(2027, 1, 2) do
      Stats::CalculateMonth.new(user.id, 2026, 12).call
      expect(user.stats.find_by!(year: 2026, month: 12).flight_distance).to eq(878_000)
    end
  end

  it 'uses the same user-local month as point stats despite the AirTrail date' do
    travel_to Time.utc(2027, 1, 2) do
      create(:flight, user: user, flight_date: Date.new(2027, 1, 1),
                      departure_time: Time.utc(2027, 1, 1, 3), arrival_time: Time.utc(2027, 1, 1, 5))
      expect(Stats::FlightDistanceQuery.new(user, 2026, 12).by_day).to eq(31 => 878_000)
      expect(Stats::FlightDistanceQuery.new(user, 2027, 1).call).to eq(0)
      expect(user.flights.stat_months(user.timezone_iana)).to eq([[2026, 12]])
    end
  end
end
