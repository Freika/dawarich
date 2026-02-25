# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1::Stats', type: :request do
  describe 'GET /index' do
    let(:user) { create(:user) }
    let(:stats_in_2020) { (1..12).map { |month| create(:stat, year: 2020, month:, user:) } }
    let(:stats_in_2021) { (1..12).map { |month| create(:stat, year: 2021, month:, user:) } }
    let(:points_in_2020) do
      (1..85).map do |i|
        create(:point, :with_geodata,
               timestamp: Time.zone.local(2020, 1, 1).to_i + i.hours,
               user:,
               country_name: 'Test Country',
               city: 'Test City',
               reverse_geocoded_at: Time.current)
      end
    end
    let(:points_in_2021) do
      (1..95).map do |i|
        create(:point, :with_geodata,
               timestamp: Time.zone.local(2021, 1, 1).to_i + i.hours,
               user:,
               country_name: 'Test Country',
               city: 'Test City',
               reverse_geocoded_at: Time.current)
      end
    end

    before do
      stats_in_2020
      stats_in_2021
      points_in_2020
      points_in_2021
    end

    let(:expected_json) do
      {
        totalDistanceKm: (stats_in_2020.map(&:distance).sum + stats_in_2021.map(&:distance).sum) / 1000,
        totalPointsTracked: points_in_2020.count + points_in_2021.count,
        totalReverseGeocodedPoints: points_in_2020.count + points_in_2021.count,
        totalCountriesVisited: 1,
        totalCitiesVisited: 1,
        yearlyStats: [
          {
            year: 2021,
            totalDistanceKm: (stats_in_2021.map(&:distance).sum / 1000).to_i,
            totalCountriesVisited: 1,
            totalCitiesVisited: 1,
            monthlyDistanceKm: {
              january: 1,
              february: 1,
              march: 1,
              april: 1,
              may: 1,
              june: 1,
              july: 1,
              august: 1,
              september: 1,
              october: 1,
              november: 1,
              december: 1
            }
          },
          {
            year: 2020,
            totalDistanceKm: (stats_in_2020.map(&:distance).sum / 1000).to_i,
            totalCountriesVisited: 1,
            totalCitiesVisited: 1,
            monthlyDistanceKm: {
              january: 1,
              february: 1,
              march: 1,
              april: 1,
              may: 1,
              june: 1,
              july: 1,
              august: 1,
              september: 1,
              october: 1,
              november: 1,
              december: 1
            }
          }
        ]
      }.to_json
    end

    it 'renders a successful response' do
      get api_v1_areas_url(api_key: user.api_key)
      expect(response).to be_successful
    end

    it 'returns the stats' do
      get api_v1_stats_url(api_key: user.api_key)

      expect(response).to be_successful
      expect(response.body).to eq(expected_json)
    end
  end
end
