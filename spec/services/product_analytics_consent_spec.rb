# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ProductAnalyticsConsent do
  let(:user) { create(:user, provider: 'google_oauth2', uid: 'google-uid-1', created_at: 2.days.ago) }

  before do
    allow(DawarichSettings).to receive(:self_hosted?).and_return(false)
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with('PRODUCT_POSTHOG_API_KEY').and_return('phc_test')
    allow(ENV).to receive(:[]).with('PRODUCT_POSTHOG_PERSONAL_API_KEY').and_return('personal_test')
    allow(ENV).to receive(:[]).with('PRODUCT_POSTHOG_PROJECT_ID').and_return('123')
    allow(PostHog).to receive(:capture) { |attrs| captured << attrs }
  end

  let(:captured) { [] }

  def signup_captures
    captured.select { |attrs| attrs[:event] == 'user_signed_up' }
  end

  it 'records the signup of an OAuth account that opts in before any activity, dated to account creation' do
    described_class.update!(user: user, consent: true)

    expect(signup_captures.size).to eq(1)
    expect(signup_captures.first).to include(distinct_id: user.reload.product_analytics_id,
                                             timestamp: user.created_at)
    expect(signup_captures.first[:properties]).to include('auth_method' => 'google', 'channel' => 'server')
  end

  it 'labels an account without a provider as an email signup' do
    email_user = create(:user)

    described_class.update!(user: email_user, consent: true)

    expect(signup_captures.first[:properties]).to include('auth_method' => 'email')
  end

  it 'does not record a signup for an account that was already tracking before opting in' do
    create(:point, user: user)

    described_class.update!(user: user, consent: true)

    expect(signup_captures).to be_empty
  end

  it 'does not record a signup for an account with a completed import before opting in' do
    import = create(:import, user: user, status: :completed)
    create(:point, user: user, import: import)

    described_class.update!(user: user, consent: true)

    expect(signup_captures).to be_empty
  end

  it 'records the signup only once when consent is confirmed again' do
    described_class.update!(user: user, consent: true)
    described_class.update!(user: user, consent: true)

    expect(signup_captures.size).to eq(1)
  end

  it 'records no signup when the account declines' do
    described_class.update!(user: user, consent: false)

    expect(PostHog).not_to have_received(:capture)
  end
end
