# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1::Users', type: :request do
  describe 'GET /me' do
    let(:user) { create(:user) }
    let(:headers) { { 'Authorization' => "Bearer #{user.api_key}" } }

    it 'returns http success' do
      get '/api/v1/users/me', headers: headers

      expect(response).to have_http_status(:success)
      expect(response.body).to include(user.email)
      expect(response.body).to include(user.id.to_s)
    end
  end
end
