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

      context 'when user is inactive' do
        before do
          user.update(status: :inactive, active_until: 1.day.ago)
        end

        it 'returns http unauthorized' do
          post "/api/v1/owntracks/points?api_key=#{user.api_key}", params: point_params

          expect(response).to have_http_status(:unauthorized)
        end
      end
    end
  end
end
