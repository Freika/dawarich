# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Insights API on self-hosted without JWT_SECRET_KEY', type: :request do
  let(:user) { create(:user) }
  let(:headers) { { 'Authorization' => "Bearer #{user.api_key}" } }

  before do
    create(:stat, year: 2024, month: 1, user: user, daily_distance: { '1' => 1000 })

    allow(DawarichSettings).to receive(:self_hosted?).and_return(true)

    env_without_jwt = ENV.to_h.tap { |h| h.delete('JWT_SECRET_KEY') }
    stub_const('ENV', env_without_jwt)
  end

  describe 'GET /api/v1/insights' do
    it 'does not raise when JWT_SECRET_KEY is unset on self-hosted' do
      get api_v1_insights_url, headers: headers

      expect(response).to have_http_status(:ok)
    end

    it 'returns a nil upgradeUrl on self-hosted' do
      get api_v1_insights_url, headers: headers

      json = JSON.parse(response.body)
      expect(json['upgradeUrl']).to be_nil
    end
  end

  describe 'GET /api/v1/insights/details' do
    it 'does not raise when JWT_SECRET_KEY is unset on self-hosted' do
      get details_api_v1_insights_url, headers: headers

      expect(response).to have_http_status(:ok)
    end
  end

  describe 'GET /trial/upgrade' do
    it 'redirects self-hosted users away instead of generating a subscription token' do
      sign_in(user)

      get '/trial/upgrade', params: { plan: 'pro', interval: 'annual' }

      expect(response).to redirect_to(root_path)
    end
  end
end
