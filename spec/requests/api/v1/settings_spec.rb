# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1::Settings', type: :request do
  let!(:user) { create(:user) }
  let!(:api_key) { user.api_key }

  describe 'PATCH /update' do
    context 'with valid request' do
      it 'returns http success' do
        patch "/api/v1/settings?api_key=#{api_key}", params: { settings: { route_opacity: 0.3 } }

        expect(response).to have_http_status(:success)
      end

      it 'updates the settings' do
        patch "/api/v1/settings?api_key=#{api_key}", params: { settings: { route_opacity: 0.3 } }

        expect(user.reload.settings['route_opacity'].to_f).to eq(0.3)
      end

      it 'returns the updated settings' do
        patch "/api/v1/settings?api_key=#{api_key}", params: { settings: { route_opacity: 0.3 } }

        expect(response.parsed_body['settings']['route_opacity'].to_f).to eq(0.3)
      end

      context 'when user is inactive' do
        before do
          user.update(status: :inactive, active_until: 1.day.ago)
        end

        it 'returns http unauthorized' do
          patch "/api/v1/settings?api_key=#{api_key}", params: { settings: { route_opacity: 0.3 } }

          expect(response).to have_http_status(:unauthorized)
        end
      end
    end

    context 'with invalid request' do
      before do
        allow_any_instance_of(User).to receive(:save).and_return(false)
      end

      it 'returns http unprocessable entity' do
        patch "/api/v1/settings?api_key=#{api_key}", params: { settings: { route_opacity: 'invalid' } }

        expect(response).to have_http_status(:unprocessable_content)
      end

      it 'returns an error message' do
        patch "/api/v1/settings?api_key=#{api_key}", params: { settings: { route_opacity: 'invalid' } }

        expect(response.parsed_body['message']).to eq('Something went wrong')
      end
    end

    context 'with transportation thresholds' do
      let(:threshold_params) do
        {
          settings: {
            transportation_thresholds: {
              walking_max_speed: 8,
              cycling_max_speed: 50
            }
          }
        }
      end

      it 'triggers recalculation when thresholds change' do
        expect do
          patch "/api/v1/settings?api_key=#{api_key}", params: threshold_params
        end.to have_enqueued_job(Tracks::TransportationModeRecalculationJob).with(user.id)

        expect(response).to have_http_status(:success)
        expect(response.parsed_body['recalculation_triggered']).to be true
      end

      context 'when recalculation is in progress' do
        before do
          Tracks::TransportationRecalculationStatus.new(user.id).start(total_tracks: 100)
        end

        it 'returns locked status' do
          patch "/api/v1/settings?api_key=#{api_key}", params: threshold_params

          expect(response).to have_http_status(:locked)
          expect(response.parsed_body['status']).to eq('locked')
        end
      end
    end
  end

  describe 'GET /transportation_recalculation_status' do
    it 'returns idle status when no recalculation is running' do
      get "/api/v1/settings/transportation_recalculation_status?api_key=#{api_key}"

      expect(response).to have_http_status(:success)
      expect(response.parsed_body['status']).to eq('idle')
    end

    it 'returns processing status when recalculation is in progress' do
      status = Tracks::TransportationRecalculationStatus.new(user.id)
      status.start(total_tracks: 100)
      status.update_progress(processed_tracks: 50, total_tracks: 100)

      get "/api/v1/settings/transportation_recalculation_status?api_key=#{api_key}"

      expect(response).to have_http_status(:success)
      expect(response.parsed_body['status']).to eq('processing')
      expect(response.parsed_body['total_tracks']).to eq(100)
      expect(response.parsed_body['processed_tracks']).to eq(50)
    end
  end
end
