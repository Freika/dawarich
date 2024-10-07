# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Map', type: :request do
  before do
    stub_request(:any, 'https://api.github.com/repos/Freika/dawarich/tags')
      .to_return(status: 200, body: '[{"name": "1.0.0"}]', headers: {})
  end

  describe 'GET /index' do
    context 'when user signed in' do
      let(:user) { create(:user) }
      let(:points) { create_list(:point, 10, user:, timestamp: 1.day.ago) }

      before { sign_in user }

      it 'returns http success' do
        get map_path

        expect(response).to have_http_status(:success)
      end
    end

    context 'when user not signed in' do
      it 'returns redirects to sign in page' do
        get map_path

        expect(response).to have_http_status(302)
      end
    end
  end
end
