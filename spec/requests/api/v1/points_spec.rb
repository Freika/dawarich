# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1::Points', type: :request do
  describe 'POST /api/v1/points' do
    context 'with valid params' do
      let(:params) do
        { lat: 1.0, lon: 1.0, tid: 'test', tst: Time.current.to_i, topic: 'iPhone 12 pro' }
      end

      it 'returns http success' do
        post api_v1_points_path, params: params

        expect(response).to have_http_status(:success)
      end

      it 'enqueues a job' do
        expect do
          post api_v1_points_path, params: params
        end.to have_enqueued_job(Owntracks::PointCreatingJob)
      end
    end
  end
end
