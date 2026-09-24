# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1::Users::AnalyticsConsent', type: :request do
  let(:user) { create(:user, skip_auto_trial: true) }
  let(:headers) { { 'Authorization' => "Bearer #{user.api_key}" } }

  before { allow(DawarichSettings).to receive(:self_hosted?).and_return(false) }

  it 'starts undecided and works for pending-payment accounts' do
    user.update!(status: :pending_payment)
    get '/api/v1/users/me/analytics_consent', headers: headers
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body).to eq('consent' => nil, 'analytics_id' => nil)
  end

  it 'requires authentication and an explicit boolean' do
    patch '/api/v1/users/me/analytics_consent', params: { consent: true }
    expect(response).to have_http_status(:unauthorized)

    patch '/api/v1/users/me/analytics_consent', params: { consent: 'yes' }, headers: headers
    expect(response).to have_http_status(:unprocessable_content)
    expect(user.reload.product_analytics_consent).to be_nil
  end

  it 'grants, revokes and rotates the pseudonymous identity' do
    patch '/api/v1/users/me/analytics_consent', params: { consent: true }, headers: headers
    expect(response).to have_http_status(:ok)
    first_id = response.parsed_body.fetch('analytics_id')
    expect(first_id).to match(/\A[0-9a-f-]{36}\z/)

    patch '/api/v1/users/me/analytics_consent', params: { consent: false }, headers: headers
    expect(response.parsed_body).to eq('consent' => false, 'analytics_id' => nil)
    expect(ProductAnalyticsErasureJob).to have_been_enqueued.with(first_id)

    patch '/api/v1/users/me/analytics_consent', params: { consent: true }, headers: headers
    expect(response.parsed_body.fetch('analytics_id')).not_to eq(first_id)
  end

  it 'rejects consent changes on self-hosted instances' do
    allow(DawarichSettings).to receive(:self_hosted?).and_return(true)
    patch '/api/v1/users/me/analytics_consent', params: { consent: true }, headers: headers
    expect(response).to have_http_status(:forbidden)
  end
end
