# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1::Countries::VisitedCities', type: :request do
  describe 'GET /index' do
    let(:user) { create(:user) }
    let(:start_at) { '2023-01-01' }
    let(:end_at) { '2023-12-31' }

    it 'returns visited cities' do
      get "/api/v1/countries/visited_cities?api_key=#{user.api_key}&start_at=#{start_at}&end_at=#{end_at}"

      expect(response).to have_http_status(:ok)
    end

    it 'ignores anomalous points the way the statistics do' do
      base = Time.utc(2023, 6, 1, 12).to_i
      create(:point, user: user, city: 'Berlin', country: 'Germany', timestamp: base)
      create(:point, user: user, city: 'Berlin', country: 'Germany', timestamp: base + 2.hours.to_i)
      create(:point, user: user, city: 'Paris', country: 'France', anomaly: true,
                     timestamp: base + 1.hour.to_i)

      get "/api/v1/countries/visited_cities?api_key=#{user.api_key}&start_at=#{start_at}&end_at=#{end_at}"

      cities = response.parsed_body['data'].flat_map { |country| country['cities'] }
      expect(cities.map { |city| city['city'] }).to eq(['Berlin'])
      expect(cities.first['stayed_for']).to eq(120)
    end
  end
end
