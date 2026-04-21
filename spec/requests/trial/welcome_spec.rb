# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'GET /trial/welcome', type: :request do
  let(:user) { create(:user, status: :trial, active_until: 7.days.from_now) }
  let(:token) { user.generate_subscription_token }

  it 'signs in the user and renders the welcome page' do
    get "/trial/welcome?token=#{token}"
    expect(response).to have_http_status(:ok)
    expect(response.body).to include('Welcome to Dawarich')
  end

  it 'rejects an invalid token' do
    get '/trial/welcome?token=not_a_real_jwt'
    expect(response).to have_http_status(:unauthorized).or have_http_status(:found) # redirect to sign_in
  end

  it 'rejects an expired token' do
    expired_token = token # generate before stubbing time so exp is based on real "now"
    allow(Time).to receive(:now).and_return(1.hour.from_now)
    get "/trial/welcome?token=#{expired_token}"
    expect(response).to have_http_status(:unauthorized).or have_http_status(:found)
  end
end
