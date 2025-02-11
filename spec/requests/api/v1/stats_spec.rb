# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1::Stats', type: :request do
  let(:user) { create(:user) }

  describe 'GET /index' do
    let!(:user) { create(:user) }
    let!(:stats_in_2020) { create_list(:stat, 12, year: 2020, user:) }
    let!(:stats_in_2021) { create_list(:stat, 12, year: 2021, user:) }
    let!(:points_in_2020) do
      (1..85).map do |i|
        create(:point, :with_geodata, :reverse_geocoded, timestamp: Time.zone.local(2020, 1, 1).to_i + i.hours, user:)
      end
    end
    let!(:points_in_2021) do
      (1..95).map do |i|
        create(:point, :with_geodata, :reverse_geocoded, timestamp: Time.zone.local(2021, 1, 1).to_i + i.hours, user:)
      end
    end
    let(:expected_json) do
      {
        totalDistanceKm: stats_in_2020.map(&:distance).sum + stats_in_2021.map(&:distance).sum,
        totalPointsTracked: points_in_2020.count + points_in_2021.count,
        totalReverseGeocodedPoints: points_in_2020.count + points_in_2021.count,
        totalCountriesVisited: 1,
        totalCitiesVisited: 1,
        yearlyStats: [
          {
            year: 2021,
            totalDistanceKm: 12,
            totalCountriesVisited: 1,
            totalCitiesVisited: 1,
            monthlyDistanceKm: {
              january: 1,
              february: 0,
              march: 0,
              april: 0,
              may: 0,
              june: 0,
              july: 0,
              august: 0,
              september: 0,
              october: 0,
              november: 0,
              december: 0
            }
          },
          {
            year: 2020,
            totalDistanceKm: 12,
            totalCountriesVisited: 1,
            totalCitiesVisited: 1,
            monthlyDistanceKm: {
              january: 1,
              february: 0,
              march: 0,
              april: 0,
              may: 0,
              june: 0,
              july: 0,
              august: 0,
              september: 0,
              october: 0,
              november: 0,
              december: 0
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
