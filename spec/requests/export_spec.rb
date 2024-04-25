# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Exports', type: :request do
  describe 'GET /create' do
    before do
      stub_request(:any, 'https://api.github.com/repos/Freika/dawarich/tags')
        .to_return(status: 200, body: '[{"name": "1.0.0"}]', headers: {})

      sign_in create(:user)
    end

    it 'returns http success' do
      get '/export'
      expect(response).to have_http_status(:success)
    end
  end
end
