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
    end

    context 'with invalid request' do
      before do
        allow_any_instance_of(User).to receive(:save).and_return(false)
      end

      it 'returns http unprocessable entity' do
        patch "/api/v1/settings?api_key=#{api_key}", params: { settings: { route_opacity: 'invalid' } }

        expect(response).to have_http_status(:unprocessable_entity)
      end

      it 'returns an error message' do
        patch "/api/v1/settings?api_key=#{api_key}", params: { settings: { route_opacity: 'invalid' } }

        expect(response.parsed_body['message']).to eq('Something went wrong')
      end
    end
  end
end
