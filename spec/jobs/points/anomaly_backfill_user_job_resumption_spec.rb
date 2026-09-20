# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Points::AnomalyBackfillUserJob, type: :job do
  describe 'resumption' do
    let(:user) { create(:user) }

    let!(:january_anomaly) do
      create(:point, user: user, accuracy: 50_000, anomaly: true,
                     timestamp: Time.utc(2026, 1, 15).to_i,
                     lonlat: 'POINT(13.405 52.52)')
    end
    let!(:march_anomaly) do
      create(:point, user: user, accuracy: 50_000, anomaly: true,
                     timestamp: Time.utc(2026, 3, 15).to_i,
                     lonlat: 'POINT(13.406 52.53)')
    end

    def month_cursor(month)
      Time.utc(2026, month, 1).to_i
    end

    it 'does not clear already re-evaluated flags a second time when it resumes' do
      described_class.perform_later(user.id, reset: true)

      interrupt_job_during_step(described_class, :filter_months, cursor: month_cursor(1)) do
        perform_enqueued_jobs(only: described_class)
      end
      perform_enqueued_jobs(only: described_class)

      expect(january_anomaly.reload.anomaly).to be true
      expect(march_anomaly.reload.anomaly).to be true
    end

    it 'defers the downstream recalculation until every month has been filtered' do
      described_class.perform_later(user.id, reset: true)

      interrupt_job_during_step(described_class, :filter_months, cursor: month_cursor(1)) do
        perform_enqueued_jobs(only: described_class)
      end

      expect(Users::RecalculateDataJob).not_to have_been_enqueued

      perform_enqueued_jobs(only: described_class)

      expect(Users::RecalculateDataJob).to have_been_enqueued.with(user.id, notify: true)
    end

    it 'completes in a single run when the worker is not shutting down' do
      perform_enqueued_jobs(only: described_class) do
        described_class.perform_later(user.id, reset: true)
      end

      expect(enqueued_jobs.select { |job| job[:job] == described_class }).to be_empty
    end
  end
end
