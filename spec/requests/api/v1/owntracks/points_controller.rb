# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1::Owntracks::Points', type: :request do
  describe 'POST /api/v1/owntracks/points' do
    context 'with valid params' do
      let(:params) do
        { lat: 1.0, lon: 1.0, tid: 'test', tst: Time.current.to_i, topic: 'iPhone 12 pro' }
      end
      let(:user) { create(:user) }

      context 'with invalid api key' do
        it 'returns http unauthorized' do
          post api_v1_points_path, params: params

          expect(response).to have_http_status(:unauthorized)
        end
      end

      context 'with valid api key' do
        it 'returns http success' do
          post api_v1_points_path(api_key: user.api_key), params: params

          expect(response).to have_http_status(:success)
        end

        it 'enqueues a job' do
          expect do
            post api_v1_points_path(api_key: user.api_key), params: params
          end.to have_enqueued_job(Owntracks::PointCreatingJob)
        end
      end
    end
  end
end
