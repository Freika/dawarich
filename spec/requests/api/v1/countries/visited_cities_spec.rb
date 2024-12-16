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
  end
end
