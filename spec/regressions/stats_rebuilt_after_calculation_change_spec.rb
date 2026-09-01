# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Stats rebuilt after the calculation changes' do
  let(:user) { create(:user, status: :active) }

  def stale_stat(month)
    create(:stat, user: user, year: 2025, month: month, calculation_version: 0)
      .tap { |stat| stat.update_column(:updated_at, 1.day.ago) }
  end

  describe 'the sweep' do
    before { create(:point, user: user, timestamp: Time.utc(2025, 12, 17, 0, 20, 0).to_i) }

    it 'collects a month whose stamp is behind, with no new points to trigger it' do
      stale_stat(12)

      expect { Stats::BulkCalculator.new(user.id).call }
        .to have_enqueued_job(Stats::CalculatingJob).with(user.id, 2025, 12, notify_on_failure: false)
    end

    it 'leaves a month already at the current stamp alone' do
      create(:stat, user: user, year: 2025, month: 12,
                    calculation_version: Stats::CalculateMonth::CALCULATION_VERSION)
        .update_column(:updated_at, 1.day.ago)

      expect { Stats::BulkCalculator.new(user.id).call }
        .not_to have_enqueued_job(Stats::CalculatingJob)
    end

    it 'takes no more than the per-run limit so a version bump cannot flood the queue' do
      limit = Stats::BulkCalculator::STALE_STATS_PER_RUN
      (1..(limit + 3)).each { |month| stale_stat(month) }

      expect { Stats::BulkCalculator.new(user.id).call }
        .to have_enqueued_job(Stats::CalculatingJob).exactly(limit).times
    end
  end

  describe 'the calculation' do
    it 'stamps the row it writes' do
      stale_stat(12)
      create(:point, user: user, lonlat: 'POINT(-74.0 40.7)',
                     timestamp: Time.utc(2025, 12, 17, 12, 0, 0).to_i)

      Stats::CalculateMonth.new(user.id, 2025, 12).call

      expect(Stat.find_by(user: user, year: 2025, month: 12).calculation_version)
        .to eq(Stats::CalculateMonth::CALCULATION_VERSION)
    end

    it 'stamps a month that turned out to have no points, so it is not collected forever' do
      stale_stat(11)

      Stats::CalculateMonth.new(user.id, 2025, 11).call

      expect(Stat.find_by(user: user, year: 2025, month: 11).calculation_version)
        .to eq(Stats::CalculateMonth::CALCULATION_VERSION)
    end
  end

  describe 'a month that keeps failing' do
    before { create(:point, user: user, timestamp: Time.utc(2025, 12, 17, 0, 20, 0).to_i) }

    it 'is marked so the repair run does not notify the user' do
      stale_stat(12)

      expect { Stats::BulkCalculator.new(user.id).call }
        .to have_enqueued_job(Stats::CalculatingJob).with(user.id, 2025, 12, notify_on_failure: false)
    end

    it 'stays silent when the repair run fails' do
      allow(Stats::CalculateMonth).to receive(:new).and_raise(StandardError, 'boom')

      expect { Stats::CalculatingJob.perform_now(user.id, 2025, 12, notify_on_failure: false) }
        .not_to change(Notification, :count)
    end

    it 'still notifies when the run was not a repair' do
      allow(Stats::CalculateMonth).to receive(:new).and_raise(StandardError, 'boom')

      expect { Stats::CalculatingJob.perform_now(user.id, 2025, 12) }
        .to change(Notification, :count).by(1)
    end

    it 'does not permanently occupy every repair slot' do
      (1..10).each { |month| stale_stat(month) }

      picked = 20.times.flat_map do
        clear_enqueued_jobs
        Stats::BulkCalculator.new(user.id).call
        enqueued_jobs.select { |job| job[:job] == Stats::CalculatingJob }.map { |job| job[:args][2] }
      end

      expect(picked.uniq.size).to be > Stats::BulkCalculator::STALE_STATS_PER_RUN
    end
  end
end
