# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'API password sign-in on OIDC-only installations', type: :request do
  let(:password) { 'SyntheticPassword123!' }
  let(:user) { create(:user, password:) }

  before do
    allow(DawarichSettings).to receive(:oidc_enabled?).and_return(true)
    stub_const('ALLOW_EMAIL_PASSWORD_LOGIN', false)
  end

  [false, true].each do |two_factor|
    it "rejects password login without issuing credentials when two-factor is #{two_factor}" do
      user.update!(otp_secret: User.generate_otp_secret, otp_required_for_login: two_factor)

      post '/api/v1/auth/login', params: { email: user.email, password: }, as: :json

      expect(response).to have_http_status(:forbidden)
      expect(response.parsed_body).not_to have_key('api_key')
      expect(response.parsed_body).not_to have_key('challenge_token')
    end
  end

  it 'returns the same disabled response for an unknown account' do
    post '/api/v1/auth/login', params: { email: 'unknown@example.test', password: }, as: :json

    expect(response).to have_http_status(:forbidden)
    expect(response.parsed_body).not_to have_key('api_key')
  end

  it 'allows password login alongside OIDC when enabled' do
    stub_const('ALLOW_EMAIL_PASSWORD_LOGIN', true)

    post '/api/v1/auth/login', params: { email: user.email, password: }, as: :json

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body['api_key']).to eq(user.api_key)
  end

  it 'allows password login without an OIDC provider' do
    allow(DawarichSettings).to receive(:oidc_enabled?).and_return(false)

    post '/api/v1/auth/login', params: { email: user.email, password: }, as: :json

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body['api_key']).to eq(user.api_key)
  end
end
