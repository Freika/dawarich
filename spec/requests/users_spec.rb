# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Users', type: :request do
  before do
    stub_request(:any, 'https://api.github.com/repos/Freika/dawarich/tags')
      .to_return(status: 200, body: '[{"name": "1.0.0"}]', headers: {})
  end

  describe 'GET /users/sign_up' do
    context 'when self-hosted' do
      before do
        stub_const('SELF_HOSTED', true)
      end

      it 'returns http success' do
        get '/users/sign_up'
        expect(response).to have_http_status(:not_found)
      end
    end

    context 'when not self-hosted' do
      before do
        stub_const('SELF_HOSTED', false)
        Rails.application.reload_routes!
      end

      it 'returns http success' do
        get '/users/sign_up'
        expect(response).to have_http_status(:success)
      end
    end
  end
end
