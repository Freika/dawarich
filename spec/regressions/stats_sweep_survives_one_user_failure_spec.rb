# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Stats sweep resilience' do
  describe 'a user whose timezone is an ActiveSupport friendly name' do
    let(:user) { create(:user, status: :active, settings: { 'timezone' => 'Eastern Time (US & Canada)' }) }

    before { create(:point, user: user, timestamp: 1.hour.ago.to_i) }

    it 'resolves the timezone to IANA instead of handing Postgres a name it rejects' do
      expect { Stats::BulkCalculator.new(user.id).call }.not_to raise_error
    end

    it 'still selects the month the points fall in' do
      expect { Stats::BulkCalculator.new(user.id).call }
        .to have_enqueued_job(Stats::CalculatingJob)
    end
  end

  describe 'one user failing mid-sweep' do
    let!(:failing_user) { create(:user, status: :active) }
    let!(:healthy_user) { create(:user, status: :active) }

    before do
      create(:point, user: healthy_user, timestamp: 1.hour.ago.to_i)

      allow(Stats::BulkCalculator).to receive(:new).and_call_original
      allow(Stats::BulkCalculator).to receive(:new).with(failing_user.id).and_raise(
        ActiveRecord::StatementInvalid, 'boom'
      )
    end

    it 'does not abort the sweep' do
      expect { BulkStatsCalculatingJob.perform_now }.not_to raise_error
    end

    it 'still processes the users behind the failure' do
      BulkStatsCalculatingJob.perform_now

      expect(Stats::BulkCalculator).to have_received(:new).with(healthy_user.id)
    end

    it 'reports the failure rather than swallowing it' do
      allow(ExceptionReporter).to receive(:call)

      BulkStatsCalculatingJob.perform_now

      expect(ExceptionReporter).to have_received(:call).with(
        an_instance_of(ActiveRecord::StatementInvalid), /#{failing_user.id}/
      )
    end
  end

  describe 'every user failing' do
    let!(:first_user) { create(:user, status: :active) }
    let!(:second_user) { create(:user, status: :active) }

    before do
      allow(Stats::BulkCalculator).to receive(:new).and_raise(ActiveRecord::StatementInvalid, 'boom')
    end

    it 'raises so the sweep is retried rather than reported as a success' do
      expect { BulkStatsCalculatingJob.perform_now }.to raise_error(Stats::SweepFailed)
    end

    it 'still attempts every user before raising' do
      expect { BulkStatsCalculatingJob.perform_now }.to raise_error(Stats::SweepFailed)

      expect(Stats::BulkCalculator).to have_received(:new).with(first_user.id)
      expect(Stats::BulkCalculator).to have_received(:new).with(second_user.id)
    end
  end

  describe 'no users to sweep' do
    it 'does not raise' do
      expect { BulkStatsCalculatingJob.perform_now }.not_to raise_error
    end
  end
end
