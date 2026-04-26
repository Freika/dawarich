# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1::Recalculations', type: :request do
  let(:user) { create(:user) }

  describe 'POST /create' do
    before { Rails.cache.delete("recalculation_pending:#{user.id}") }

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

    it 'returns 409 when a recalculation is already pending for the user' do
      Rails.cache.write("recalculation_pending:#{user.id}", true, expires_in: 30.minutes)

      expect do
        post "/api/v1/recalculations?api_key=#{user.api_key}"
      end.not_to have_enqueued_job(Users::RecalculateDataJob)

      expect(response).to have_http_status(:conflict)
    end

    it 'rejects an out-of-range year with 400' do
      post "/api/v1/recalculations?api_key=#{user.api_key}", params: { year: 1500 }

      expect(response).to have_http_status(:bad_request)
    end

    it 'requires authentication' do
      post '/api/v1/recalculations'

      expect(response).to have_http_status(:unauthorized)
    end
  end
end
