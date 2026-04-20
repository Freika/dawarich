# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1::Users::Destroy', type: :request do
  describe 'DELETE /api/v1/users/me' do
    let(:user) { create(:user) }
    let(:headers) { { 'Authorization' => "Bearer #{user.api_key}" } }

    it 'calls Users::Destroy.new(user).call on the current user' do
      destroy_service = instance_double(Users::Destroy, call: true)
      expect(Users::Destroy).to receive(:new).with(an_instance_of(User)).and_return(destroy_service)
      expect(destroy_service).to receive(:call)

      delete '/api/v1/users/me', headers: headers
    end

    it 'returns 401 without auth' do
      delete '/api/v1/users/me'

      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns 200 with a confirmation message' do
      allow_any_instance_of(Users::Destroy).to receive(:call).and_return(true)

      delete '/api/v1/users/me', headers: headers

      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)['message']).to be_present
    end
  end
end
