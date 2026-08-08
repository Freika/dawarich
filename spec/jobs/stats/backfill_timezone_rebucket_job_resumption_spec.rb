# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Stats::BackfillTimezoneRebucketJob do
  describe 'resumption' do
    let(:user) { create(:user) }
    let!(:stats) do
      (1..6).map { |month| create(:stat, user: user, year: 2026, month: month) }
    end

    def rebucketed_months
      enqueued_jobs
        .select { |job| job[:job] == Stats::CalculatingJob }
        .map { |job| job[:args][2] }
    end

    it 'stops partway through when the worker is shutting down' do
      described_class.perform_later(batch_size: 2)

      interrupt_job_during_step(described_class, :rebucket, cursor: stats[3].id) do
        perform_enqueued_jobs(only: described_class)
      end

      expect(rebucketed_months).to eq([1, 2, 3, 4])
    end

    it 'does not re-enqueue the stats it already fanned out when it resumes' do
      described_class.perform_later(batch_size: 2)

      interrupt_job_during_step(described_class, :rebucket, cursor: stats[3].id) do
        perform_enqueued_jobs(only: described_class)
      end
      perform_enqueued_jobs(only: described_class)

      expect(rebucketed_months).to eq([1, 2, 3, 4, 5, 6])
    end

    it 'completes in a single run when the worker is not shutting down' do
      perform_enqueued_jobs(only: described_class) { described_class.perform_later(batch_size: 2) }

      expect(rebucketed_months).to eq([1, 2, 3, 4, 5, 6])
    end
  end
end
