# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Web product analytics', type: :request do
  let(:user) { create(:user, product_analytics_consent: true, product_analytics_id: SecureRandom.uuid) }

  before do
    allow(DawarichSettings).to receive(:self_hosted?).and_return(false)
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with('PRODUCT_POSTHOG_API_KEY').and_return('phc_test')
    allow(ENV).to receive(:[]).with('PRODUCT_POSTHOG_PERSONAL_API_KEY').and_return('personal_test')
    allow(ENV).to receive(:[]).with('PRODUCT_POSTHOG_PROJECT_ID').and_return('123')
    allow(PostHog).to receive(:capture).and_return(true)
    sign_in user
  end

  it 'records the first consented signed-in web observation once' do
    2.times { post '/product_analytics_events', params: { event: 'web_first_observed' } }

    expect(response).to have_http_status(:accepted)
    expect(user.reload.product_analytics_web_observed_at).to be_present
    expect(PostHog).to have_received(:capture).with(hash_including(event: 'web_first_observed')).once
  end

  it 'refuses capture after withdrawal' do
    user.update!(product_analytics_consent: false, product_analytics_id: nil)
    post '/product_analytics_events', params: { event: 'web_first_observed' }

    expect(response).to have_http_status(:forbidden)
    expect(PostHog).not_to have_received(:capture)
  end
end
