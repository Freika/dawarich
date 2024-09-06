# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1::Healths', type: :request do
  describe 'GET /index' do
    context 'when user is not authenticated' do
      it 'returns http success' do
        get '/api/v1/health'

        expect(response).to have_http_status(:success)
      end
    end
  end
end
