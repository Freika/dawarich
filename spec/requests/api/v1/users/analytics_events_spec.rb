# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1::Users::AnalyticsEvents', type: :request do
  let(:user) do
    create(:user, skip_auto_trial: true, product_analytics_consent: true, product_analytics_id: SecureRandom.uuid)
  end
  let(:headers) { { 'Authorization' => "Bearer #{user.api_key}" } }

  before do
    allow(DawarichSettings).to receive(:self_hosted?).and_return(false)
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with('PRODUCT_POSTHOG_API_KEY').and_return('phc_test')
    allow(ENV).to receive(:[]).with('PRODUCT_POSTHOG_PERSONAL_API_KEY').and_return('personal_test')
    allow(ENV).to receive(:[]).with('PRODUCT_POSTHOG_PROJECT_ID').and_return('123')
  end

  it 'returns a retryable response when capture is unavailable' do
    allow(PostHog).to receive(:capture).and_return(false, true)
    params = { event: 'mobile_first_observed', platform: 'ios', properties: { installation_cohort: 'new' } }

    post '/api/v1/users/me/analytics_events', params: params, headers: headers
    expect(response).to have_http_status(:service_unavailable)

    post '/api/v1/users/me/analytics_events', params: params, headers: headers
    expect(response).to have_http_status(:accepted)
  end
end
