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
      let!(:stats_in_2020) { (1..12).map { |month| create(:stat, year: 2020, month:, user:) } }
      let!(:stats_in_2021) { (1..12).map { |month| create(:stat, year: 2021, month:, user:) } }
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
                "february": 1,
                "march": 1,
                "april": 1,
                "may": 1,
                "june": 1,
                "july": 1,
                "august": 1,
                "september": 1,
                "october": 1,
                "november": 1,
                "december": 1
              }
            },
            {
              "year": 2020,
              "totalDistanceKm": (stats_in_2020.map(&:distance).sum / 1000).to_i,
              "totalCountriesVisited": 1,
              "totalCitiesVisited": 1,
              "monthlyDistanceKm": {
                "january": 1,
                "february": 1,
                "march": 1,
                "april": 1,
                "may": 1,
                "june": 1,
                "july": 1,
                "august": 1,
                "september": 1,
                "october": 1,
                "november": 1,
                "december": 1
              }
            }
          ]
        }.to_json
      end

      it 'returns the expected JSON' do
        expect(serializer).to eq(expected_json)
      end
    end

    context 'when years have different countries' do
      let!(:stat_2020) do
        create(:stat, year: 2020, month: 1, user:, toponyms: [
                 { 'country' => 'France', 'cities' => [{ 'city' => 'Paris', 'points' => 5, 'stayed_for' => 120 }] }
               ])
      end
      let!(:stat_2021) do
        create(:stat, year: 2021, month: 1, user:, toponyms: [
                 { 'country' => 'Germany', 'cities' => [{ 'city' => 'Berlin', 'points' => 5, 'stayed_for' => 120 }] },
                 { 'country' => 'Spain', 'cities' => [{ 'city' => 'Madrid', 'points' => 3, 'stayed_for' => 90 }] }
               ])
      end

      it 'returns per-year country and city counts' do
        result = JSON.parse(serializer)
        yearly = result['yearlyStats']

        year_2021 = yearly.find { |y| y['year'] == 2021 }
        year_2020 = yearly.find { |y| y['year'] == 2020 }

        expect(year_2021['totalCountriesVisited']).to eq(2)
        expect(year_2021['totalCitiesVisited']).to eq(2)
        expect(year_2020['totalCountriesVisited']).to eq(1)
        expect(year_2020['totalCitiesVisited']).to eq(1)
      end
    end

    context 'when toponyms include flyover countries with empty cities' do
      let!(:stat_with_flyover) do
        create(:stat, year: 2020, month: 1, user:, toponyms: [
                 { 'country' => 'France', 'cities' => [{ 'city' => 'Paris', 'points' => 5, 'stayed_for' => 120 }] },
                 { 'country' => 'Germany', 'cities' => [] }
               ])
      end

      it 'excludes flyover countries from yearly counts' do
        result = JSON.parse(serializer)
        yearly = result['yearlyStats']

        year_2020 = yearly.find { |y| y['year'] == 2020 }
        expect(year_2020['totalCountriesVisited']).to eq(1)
      end
    end
  end
end
