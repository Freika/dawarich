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

      context 'when point creation exhausts deadlock retries' do
        before do
          allow(Traccar::PointCreator).to receive(:new)
            .and_raise(ActiveRecord::Deadlocked, 'deadlock detected')
          allow(Rails.logger).to receive(:error)
        end

        it 'logs the failure and returns a JSON 500' do
          post "/api/v1/traccar/points?api_key=#{user.api_key}", params: payload, as: :json

          expect(response).to have_http_status(:internal_server_error)
          expect(JSON.parse(response.body)).to include('error')
          expect(Rails.logger).to have_received(:error).with(/Point creation failed: ActiveRecord::Deadlocked/)
        end
      end

      context 'when payload is malformed' do
        before { payload[:location][:timestamp] = 'not-a-date' }

        it 'rejects the request and does not create a point' do
          expect do
            post "/api/v1/traccar/points?api_key=#{user.api_key}", params: payload, as: :json
          end.not_to change(Point, :count)

          expect(response).to have_http_status(:unprocessable_content)
          expect(JSON.parse(response.body)).to include('error')
        end
      end

      context 'with the form payload Traccar Client 10 sends' do
        let(:form) do
          { id: 'pixel-frey', lat: '52.52', lon: '13.405', timestamp: '1777000000', accuracy: '5.0',
            altitude: '42.0', speed: '2.72', bearing: '90.0', batt: '85.0', charge: 'true' }
        end

        it 'creates a point with the speed converted from knots' do
          expect do
            post "/api/v1/traccar/points?api_key=#{user.api_key}", params: form
          end.to change(Point, :count).by(1)

          point = user.points.last
          expect(point.timestamp).to eq(1_777_000_000)
          expect(point.velocity.to_f).to be_within(0.01).of(1.4)
          expect(point.battery).to eq(85)
        end

        it 'accepts a heartbeat without a position so the client can move on' do
          expect do
            post "/api/v1/traccar/points?api_key=#{user.api_key}",
                 params: { id: 'pixel-frey', timestamp: '1777000000' }
          end.not_to change(Point, :count)

          expect(response).to have_http_status(:ok)
        end

        it 'still rejects coordinates it cannot read instead of dropping them with a 200' do
          post "/api/v1/traccar/points?api_key=#{user.api_key}",
               params: { id: 'pixel-frey', latitude: '52.52', longitude: '13.405', timestamp: '1777000000' }

          expect(response).to have_http_status(:unprocessable_content)
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
