# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1::Traccar::Points', type: :request do
  describe 'POST /api/v1/traccar/points' do
    let(:payload) do
      {
        device_id: 'iphone-frey',
        location: {
          timestamp: '2026-04-23T12:34:56Z',
          latitude: 52.52,
          longitude: 13.405,
          accuracy: 5,
          speed: 1.4,
          altitude: 42
        },
        battery: { level: 0.85, is_charging: true },
        activity: { type: 'walking' }
      }
    end

    context 'with invalid api key' do
      it 'returns http unauthorized' do
        post '/api/v1/traccar/points', params: payload, as: :json

        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'with valid api key' do
      let(:user) { create(:user) }

      it 'returns ok' do
        post "/api/v1/traccar/points?api_key=#{user.api_key}", params: payload, as: :json

        expect(response).to have_http_status(:ok)
      end

      it 'creates a point' do
        expect do
          post "/api/v1/traccar/points?api_key=#{user.api_key}", params: payload, as: :json
        end.to change(Point, :count).by(1)
      end

      it 'enqueues anomaly filter job' do
        expect do
          post "/api/v1/traccar/points?api_key=#{user.api_key}", params: payload, as: :json
        end.to have_enqueued_job(Points::AnomalyFilterJob)
      end

      context 'when payload is malformed' do
        before { payload[:location][:timestamp] = 'not-a-date' }

        it 'returns ok and does not create a point' do
          expect do
            post "/api/v1/traccar/points?api_key=#{user.api_key}", params: payload, as: :json
          end.not_to change(Point, :count)

          expect(response).to have_http_status(:ok)
        end
      end

      context 'when user is inactive' do
        before { user.update(status: :inactive, active_until: 1.day.ago) }

        it 'returns http unauthorized' do
          post "/api/v1/traccar/points?api_key=#{user.api_key}", params: payload, as: :json

          expect(response).to have_http_status(:unauthorized)
        end
      end
    end
  end
end
