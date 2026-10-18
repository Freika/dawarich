# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Digest calculation when a monthly statistic fails', type: :job do
  let(:user) { create(:user, settings: { 'locale' => 'en' }) }

  before do
    allow_any_instance_of(Stats::CalculateMonth).to receive(:points).and_raise(StandardError, 'boom')
    allow(ExceptionReporter).to receive(:call)
  end

  it 'reports a monthly digest failure with a single notification' do
    Users::Digests::Monthly::CalculatingJob.perform_now(user.id, 2026, 4)

    title = I18n.t('jobs.users.digests.monthly.calculating_job.monthly_digest_calculation_failed')
    expect(user.notifications.error.pluck(:title)).to eq([title])
  end

  it 'reports a yearly digest failure with a single notification' do
    Users::Digests::Yearly::CalculatingJob.perform_now(user.id, 2026)

    stats_title = I18n.t('services.stats.calculate_month.stats_update_failed')
    expect(user.notifications.error.count).to eq(1)
    expect(user.notifications.error.pick(:title)).not_to eq(stats_title)
  end
end
