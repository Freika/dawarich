# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1::Recalculations', type: :request do
  let(:user) { create(:user) }

  describe 'POST /create' do
    it 'enqueues Users::RecalculateDataJob for the current user' do
      expect do
        post "/api/v1/recalculations?api_key=#{user.api_key}"
      end.to have_enqueued_job(Users::RecalculateDataJob).with(user.id, year: nil)

      expect(response).to have_http_status(:accepted)
    end

    it 'forwards an optional year parameter' do
      expect do
        post "/api/v1/recalculations?api_key=#{user.api_key}", params: { year: 2024 }
      end.to have_enqueued_job(Users::RecalculateDataJob).with(user.id, year: 2024)
    end

    it 'requires authentication' do
      post '/api/v1/recalculations'

      expect(response).to have_http_status(:unauthorized)
    end
  end
end
