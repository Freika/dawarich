# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1::Overland::Batches', type: :request do
  describe 'POST /index' do
    let(:file_path) { 'spec/fixtures/files/overland/geodata.json' }
    let(:file) { File.open(file_path) }
    let(:json) { JSON.parse(file.read) }
    let(:params) { json }

    context 'with invalid api key' do
      it 'returns http unauthorized' do
        post '/api/v1/overland/batches', params: params

        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'with valid api key' do
      let(:user) { create(:user) }

      it 'returns http success' do
        post "/api/v1/overland/batches?api_key=#{user.api_key}", params: params

        expect(response).to have_http_status(:created)
      end

      it 'creates points immediately' do
        expect do
          post "/api/v1/overland/batches?api_key=#{user.api_key}", params: params
        end.to change(Point, :count).by(1)
      end

      context 'when batch creation exhausts deadlock retries' do
        before do
          allow(Overland::PointsCreator).to receive(:new)
            .and_raise(ActiveRecord::Deadlocked, 'deadlock detected')
          allow(Rails.logger).to receive(:error)
        end

        it 'logs the failure and returns a JSON 500' do
          post "/api/v1/overland/batches?api_key=#{user.api_key}", params: params

          expect(response).to have_http_status(:internal_server_error)
          expect(JSON.parse(response.body)).to include('error')
          expect(Rails.logger).to have_received(:error).with(/Batch creation failed: ActiveRecord::Deadlocked/)
        end
      end

      context 'when user is inactive' do
        before do
          user.update(status: :inactive, active_until: 1.day.ago)
        end

        it 'returns http unauthorized' do
          post "/api/v1/overland/batches?api_key=#{user.api_key}", params: params

          expect(response).to have_http_status(:unauthorized)
        end
      end

      context 'when user is inactive but active_until is in the future' do
        before do
          user.update(status: :inactive, active_until: 1.day.from_now)
        end

        it 'returns http unauthorized' do
          post "/api/v1/overland/batches?api_key=#{user.api_key}", params: params

          expect(response).to have_http_status(:unauthorized)
        end
      end
    end
  end
end
