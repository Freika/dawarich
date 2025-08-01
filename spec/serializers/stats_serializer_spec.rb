# frozen_string_literal: true

require 'rails_helper'

RSpec.describe StatsSerializer do
  describe '#call' do
    subject(:serializer) { described_class.new(user).call }

    let!(:user) { create(:user) }

    context 'when the user has no stats' do
      let(:expected_json) do
        {
          "totalDistanceKm": 0,
          "totalPointsTracked": 0,
          "totalReverseGeocodedPoints": 0,
          "totalCountriesVisited": 0,
          "totalCitiesVisited": 0,
          "yearlyStats": []
        }.to_json
      end

      it 'returns the expected JSON' do
        expect(serializer).to eq(expected_json)
      end
    end

    context 'when the user has stats' do
      let!(:stats_in_2020) { create_list(:stat, 12, year: 2020, user:) }
      let!(:stats_in_2021) { create_list(:stat, 12, year: 2021, user:) }
      let!(:points_in_2020) do
        (1..85).map do |i|
          create(:point, :with_geodata,
                 timestamp: Time.zone.local(2020, 1, 1).to_i + i.hours,
                 user:,
                 country_name: 'Test Country',
                 city: 'Test City',
                 reverse_geocoded_at: Time.current)
        end
      end
      let!(:points_in_2021) do
        (1..95).map do |i|
          create(:point, :with_geodata,
                 timestamp: Time.zone.local(2021, 1, 1).to_i + i.hours,
                 user:,
                 country_name: 'Test Country',
                 city: 'Test City',
                 reverse_geocoded_at: Time.current)
        end
      end
      let(:expected_json) do
        {
          "totalDistanceKm": (stats_in_2020.map(&:distance).sum + stats_in_2021.map(&:distance).sum) / 1000,
          "totalPointsTracked": points_in_2020.count + points_in_2021.count,
          "totalReverseGeocodedPoints": points_in_2020.count + points_in_2021.count,
          "totalCountriesVisited": 1,
          "totalCitiesVisited": 1,
          "yearlyStats": [
            {
              "year": 2021,
              "totalDistanceKm": (stats_in_2021.map(&:distance).sum / 1000).to_i,
              "totalCountriesVisited": 1,
              "totalCitiesVisited": 1,
              "monthlyDistanceKm": {
                "january": 1,
                "february": 0,
                "march": 0,
                "april": 0,
                "may": 0,
                "june": 0,
                "july": 0,
                "august": 0,
                "september": 0,
                "october": 0,
                "november": 0,
                "december": 0
              }
            },
            {
              "year": 2020,
              "totalDistanceKm": (stats_in_2020.map(&:distance).sum / 1000).to_i,
              "totalCountriesVisited": 1,
              "totalCitiesVisited": 1,
              "monthlyDistanceKm": {
                "january": 1,
                "february": 0,
                "march": 0,
                "april": 0,
                "may": 0,
                "june": 0,
                "july": 0,
                "august": 0,
                "september": 0,
                "october": 0,
                "november": 0,
                "december": 0
              }
            }
          ]
        }.to_json
      end

      it 'returns the expected JSON' do
        expect(serializer).to eq(expected_json)
      end
    end
  end
end
