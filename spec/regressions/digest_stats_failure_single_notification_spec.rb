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

  context 'with what the user gets to read' do
    before { allow(Rails.logger).to receive(:error) }

    it 'keeps the stack trace of a failed monthly digest in the log, not in the notification' do
      Users::Digests::Monthly::CalculatingJob.perform_now(user.id, 2026, 4)

      expect(user.notifications.error.pick(:content)).to eq('boom')
      expect(Rails.logger).to have_received(:error).with(/Monthly digest.*boom.*\.rb:\d+/m)
    end

    it 'keeps the stack trace of a failed yearly digest in the log, not in the notification' do
      Users::Digests::Yearly::CalculatingJob.perform_now(user.id, 2026)

      expect(user.notifications.error.pick(:content)).to eq('boom')
      expect(Rails.logger).to have_received(:error).with(/Yearly digest.*boom.*\.rb:\d+/m)
    end

    it 'leaves the stack trace out of a failed statistics notification' do
      expect { Stats::CalculatingJob.perform_now(user.id, 2026, 4) }.to raise_error(StandardError, 'boom')

      expect(user.notifications.error.pluck(:content)).to eq(['boom'])
    end
  end

  context 'on Cloud' do
    before { allow(DawarichSettings).to receive(:self_hosted?).and_return(false) }

    it 'reports a monthly digest failure to the error tracker instead of the user' do
      Users::Digests::Monthly::CalculatingJob.perform_now(user.id, 2026, 4)

      expect(user.notifications.count).to eq(0)
      expect(ExceptionReporter).to have_received(:call).with(an_instance_of(StandardError), /monthly digest/i)
    end

    it 'reports a yearly digest failure to the error tracker instead of the user' do
      Users::Digests::Yearly::CalculatingJob.perform_now(user.id, 2026)

      expect(user.notifications.count).to eq(0)
      expect(ExceptionReporter).to have_received(:call).with(an_instance_of(StandardError), /yearly digest/i)
    end

    it 'does not tell the user about a failed statistics update' do
      expect { Stats::CalculatingJob.perform_now(user.id, 2026, 4) }.to raise_error(StandardError, 'boom')

      expect(user.notifications.count).to eq(0)
    end
  end
end
