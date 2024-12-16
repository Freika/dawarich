# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1::Points::TrackedMonths', type: :request do
  describe 'GET /index' do
    let(:user) { create(:user) }

    it 'returns tracked months' do
      get "/api/v1/points/tracked_months?api_key=#{user.api_key}"

      expect(response).to have_http_status(:ok)
    end
  end
end
