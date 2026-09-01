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

    before do
      allow(Stats::HexagonCalculator).to receive(:new).and_raise(StandardError, 'boom')
    end

    it 'stays silent when the failure happens inside a repair run' do
      expect { Stats::CalculateMonth.new(user.id, 2025, 12, notify_on_failure: false).call }
        .not_to change(Notification, :count)
    end

    it 'still notifies when the failure happens outside a repair run' do
      expect { Stats::CalculateMonth.new(user.id, 2025, 12).call }
        .to change(Notification, :count).by(1)
    end

    it 'reports every failure to the exception tracker, repair or not' do
      allow(ExceptionReporter).to receive(:call)

      Stats::CalculateMonth.new(user.id, 2025, 12, notify_on_failure: false).call

      expect(ExceptionReporter).to have_received(:call).with(an_instance_of(StandardError), /#{user.id}/)
    end

    it 'does not permanently occupy every repair slot' do
      (1..10).each { |month| stale_stat(month) }

      picked = 4.times.flat_map do
        clear_enqueued_jobs
        Stats::BulkCalculator.new(user.id).call
        enqueued_jobs.select { |job| job[:job] == Stats::CalculatingJob }.map { |job| job[:args][2] }
      end

      expect(picked.uniq.size).to be > Stats::BulkCalculator::STALE_STATS_PER_RUN
    end
  end

  describe 'the repair path and the new-points watermark' do
    it 'does not let a repair rebuild swallow the next window' do
      stale_stat(12)
      Stats::BulkCalculator.new(user.id).call
      swept = user.reload.stats_swept_at

      Stat.where(user: user).update_all(updated_at: 1.hour.from_now)

      expect(user.reload.stats_swept_at).to eq(swept)
    end

    it 'records its own high-water mark rather than deriving it from stat rows' do
      expect { Stats::BulkCalculator.new(user.id).call }
        .to change { user.reload.stats_swept_at }.from(nil)
    end

    it 'spreads repairs across the jitter window instead of one burst' do
      (1..5).each { |month| stale_stat(month) }

      Stats::BulkCalculator.new(user.id).call

      waits = enqueued_jobs.select { |job| job[:job] == Stats::CalculatingJob }.map { |job| job[:at] }

      expect(waits).to all(be_present)
      expect(waits.max - Time.current.to_f).to be <= Stats::BulkCalculator::REPAIR_JITTER.to_i
    end

    it 'does not delay a month that has genuinely new points' do
      create(:point, user: user, timestamp: Time.current.to_i)

      Stats::BulkCalculator.new(user.id).call

      waits = enqueued_jobs.select { |job| job[:job] == Stats::CalculatingJob }.map { |job| job[:at] }
      expect(waits).to all(be_nil)
    end

    it 'sends a just-scheduled month to the back of the queue' do
      (1..12).each { |month| stale_stat(month) }

      Stats::BulkCalculator.new(user.id).call
      first_pass = enqueued_jobs.select { |j| j[:job] == Stats::CalculatingJob }.map { |j| j[:args][2] }
      clear_enqueued_jobs
      Stats::BulkCalculator.new(user.id).call
      second_pass = enqueued_jobs.select { |j| j[:job] == Stats::CalculatingJob }.map { |j| j[:args][2] }

      expect(second_pass & first_pass).to be_empty
    end
  end
end
