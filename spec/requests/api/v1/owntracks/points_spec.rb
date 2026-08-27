# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1::Owntracks::Points', type: :request do
  describe 'POST /api/v1/owntracks/points' do
    let(:file_path) { 'spec/fixtures/files/owntracks/2024-03.rec' }
    let(:json) { OwnTracks::RecParser.new(File.read(file_path)).call }
    let(:point_params) { json.first }

    context 'with invalid api key' do
      it 'returns http unauthorized' do
        post '/api/v1/owntracks/points', params: point_params

        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'with valid api key' do
      let(:user) { create(:user) }

      it 'returns ok' do
        post "/api/v1/owntracks/points?api_key=#{user.api_key}", params: point_params

        expect(response).to have_http_status(:ok)
      end

      it 'creates a point immediately' do
        expect do
          post "/api/v1/owntracks/points?api_key=#{user.api_key}", params: point_params
        end.to change(Point, :count).by(1)
      end

      context 'when point creation exhausts deadlock retries' do
        before do
          allow(OwnTracks::PointCreator).to receive(:new)
            .and_raise(ActiveRecord::Deadlocked, 'deadlock detected')
          allow(Rails.logger).to receive(:error)
        end

        it 'logs the failure and returns a JSON 500' do
          post "/api/v1/owntracks/points?api_key=#{user.api_key}", params: point_params

          expect(response).to have_http_status(:internal_server_error)
          expect(JSON.parse(response.body)).to include('error')
          expect(Rails.logger).to have_received(:error).with(/Point creation failed: ActiveRecord::Deadlocked/)
        end
      end

      context 'when user is inactive' do
        before do
          user.update(status: :inactive, active_until: 1.day.ago)
        end

        it 'returns http unauthorized' do
          post "/api/v1/owntracks/points?api_key=#{user.api_key}", params: point_params

          expect(response).to have_http_status(:unauthorized)
        end
      end

      context 'when a family member shares their location' do
        let(:family) { create(:family, creator: user) }
        let(:relative) { create(:user) }

        before do
          create(:family_membership, family: family, user: user, role: :owner)
          create(:family_membership, family: family, user: relative)
          relative.update_family_location_sharing!(true, duration: 'permanent')
          create(:point, user: relative, timestamp: 1.hour.ago.to_i)
        end

        it 'answers with their card and location for OwnTracks to show' do
          post "/api/v1/owntracks/points?api_key=#{user.api_key}", params: point_params

          expect(response).to have_http_status(:ok)
          expect(JSON.parse(response.body).map { _1['_type'] }).to eq(%w[card location])
        end
      end

      context 'when formatting family locations fails' do
        before do
          allow(OwnTracks::FriendsFormatter).to receive(:new).and_raise(StandardError, 'boom')
          allow(Rails.logger).to receive(:error)
        end

        it 'still accepts the point rather than making OwnTracks resend it' do
          expect do
            post "/api/v1/owntracks/points?api_key=#{user.api_key}", params: point_params
          end.to change(Point, :count).by(1)

          expect(response).to have_http_status(:ok)
          expect(JSON.parse(response.body)).to eq([])
          expect(Rails.logger).to have_received(:error).with(/OwnTracks friends formatting failed/)
        end
      end

      context 'when user is inactive but active_until is in the future' do
        before do
          user.update(status: :inactive, active_until: 1.day.from_now)
        end

        it 'returns http unauthorized' do
          post "/api/v1/owntracks/points?api_key=#{user.api_key}", params: point_params

          expect(response).to have_http_status(:unauthorized)
        end
      end
    end
  end
end
