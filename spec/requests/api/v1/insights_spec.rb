# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1::Insights', type: :request do
  let(:user) { create(:user) }
  let(:headers) { { 'Authorization' => "Bearer #{user.api_key}" } }

  let!(:full_year_stats) do
    (1..12).map do |month|
      create(:stat, year: 2024, month: month, user: user,
                    daily_distance: { '1' => 1000, '2' => 2000, '15' => 500 })
    end
  end

  let!(:partial_year_stats) do
    (1..6).map do |month|
      create(:stat, year: 2023, month: month, user: user,
                    daily_distance: { '1' => 800, '10' => 1500 })
    end
  end

  describe 'GET /api/v1/insights' do
    it 'returns http unauthorized without api key' do
      get api_v1_insights_url

      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns overview data for the most recent year by default' do
      get api_v1_insights_url, headers: headers

      expect(response).to be_successful

      json = JSON.parse(response.body)
      expect(json['year']).to eq(2024)
      expect(json['availableYears']).to eq([2024, 2023])
      expect(json['totals']).to be_present
      expect(json['totals']['totalDistance']).to be_a(Integer)
      expect(json['totals']['distanceUnit']).to eq('km')
      expect(json['totals']['countriesCount']).to be_a(Integer)
      expect(json['totals']['citiesCount']).to be_a(Integer)
      expect(json['totals']['countriesList']).to be_an(Array)
      expect(json['totals']['daysTraveling']).to be_a(Integer)
      expect(json['activityHeatmap']).to be_present
      expect(json['activityHeatmap']['dailyData']).to be_a(Hash)
      expect(json['activityHeatmap']['activityLevels']).to be_a(Hash)
      expect(json['activityHeatmap']['activeDays']).to be_a(Integer)
      expect(json['activityHeatmap']['currentStreak']).to be_a(Integer)
      expect(json['activityHeatmap']['longestStreak']).to be_a(Integer)
    end

    it 'returns overview data for a specified year' do
      get api_v1_insights_url, headers: headers, params: { year: 2023 }

      expect(response).to be_successful

      json = JSON.parse(response.body)
      expect(json['year']).to eq(2023)
    end

    it 'respects distance_unit override param' do
      get api_v1_insights_url, headers: headers, params: { distance_unit: 'mi' }

      expect(response).to be_successful

      json = JSON.parse(response.body)
      expect(json['totals']['distanceUnit']).to eq('mi')
    end

    it 'sets Cache-Control header' do
      get api_v1_insights_url, headers: headers

      expect(response.headers['Cache-Control']).to include('max-age=300')
      expect(response.headers['Cache-Control']).to include('private')
    end
  end

  describe 'GET /api/v1/insights/details' do
    it 'returns http unauthorized without api key' do
      get details_api_v1_insights_url

      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns comparison and travel patterns for the most recent year' do
      get details_api_v1_insights_url, headers: headers

      expect(response).to be_successful

      json = JSON.parse(response.body)
      expect(json['year']).to eq(2024)
      expect(json['comparison']).to be_present
      expect(json['comparison']['previousYear']).to eq(2023)
      expect(json['comparison']['distanceChangePercent']).to be_a(Integer)
      expect(json['comparison']['countriesChange']).to be_a(Integer)
      expect(json['comparison']['citiesChange']).to be_a(Integer)
      expect(json['comparison']['daysChange']).to be_a(Integer)
      expect(json['travelPatterns']).to be_present
      expect(json['travelPatterns']['timeOfDay']).to be_a(Hash)
      expect(json['travelPatterns']['dayOfWeek']).to be_an(Array)
      expect(json['travelPatterns']['seasonality']).to be_a(Hash)
      expect(json['travelPatterns']['activityBreakdown']).to be_a(Hash)
      expect(json['travelPatterns']['topVisitedLocations']).to be_an(Array)
    end

    it 'returns nil comparison when no previous year data exists' do
      get details_api_v1_insights_url, headers: headers, params: { year: 2023 }

      expect(response).to be_successful

      json = JSON.parse(response.body)
      expect(json['comparison']).to be_nil
    end

    it 'sets Cache-Control header' do
      get details_api_v1_insights_url, headers: headers

      expect(response.headers['Cache-Control']).to include('max-age=300')
      expect(response.headers['Cache-Control']).to include('private')
    end
  end
end
