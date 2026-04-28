# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1::Users::Destroy', type: :request do
  describe 'DELETE /api/v1/users/me' do
    let(:user) { create(:user) }
    let(:headers) { { 'Authorization' => "Bearer #{user.api_key}" } }

    it 'deletes the current user' do
      user # materialize before request
      expect do
        delete '/api/v1/users/me', headers: headers
      end.to change(User.unscoped, :count).by(-1)

      expect(User.unscoped.find_by(id: user.id)).to be_nil
    end

    it 'returns 401 without auth' do
      delete '/api/v1/users/me'

      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns 200 with a confirmation message' do
      delete '/api/v1/users/me', headers: headers

      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)['message']).to be_present
    end
  end
end
