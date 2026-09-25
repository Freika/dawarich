# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ProductAnalyticsActivationJob, type: :job do
  let(:user) { create(:user, product_analytics_consent: true, product_analytics_id: SecureRandom.uuid) }

  before do
    allow(DawarichSettings).to receive(:self_hosted?).and_return(false)
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with('PRODUCT_POSTHOG_API_KEY').and_return('phc_test')
    allow(ENV).to receive(:[]).with('PRODUCT_POSTHOG_PERSONAL_API_KEY').and_return('personal_test')
    allow(ENV).to receive(:[]).with('PRODUCT_POSTHOG_PROJECT_ID').and_return('123')
    allow(PostHog).to receive(:capture).and_return(true)
  end

  it 'activates once after ten non-import points' do
    create_list(:point, 9, user: user, import: nil)
    described_class.perform_now(user.id)
    expect(user.reload.product_analytics_activated_at).to be_nil

    create(:point, user: user, import: nil)
    2.times { described_class.perform_now(user.id) }
    expect(user.reload.product_analytics_activated_at).to be_present
    expect(PostHog).to have_received(:capture).with(hash_including(event: 'user_activated')).once
    expect(PostHog).to have_received(:capture).with(hash_including(event: 'first_point_received')).once
  end

  it 'never counts a demo import as activation' do
    import = create(:import, user: user, demo: true, status: :completed)
    create(:point, user: user, import: import)
    described_class.perform_now(user.id, import_id: import.id)
    expect(user.reload.product_analytics_activated_at).to be_nil
    expect(PostHog).not_to have_received(:capture).with(hash_including(event: 'import_completed'))
  end
end
