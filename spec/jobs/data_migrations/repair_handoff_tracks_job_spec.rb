# frozen_string_literal: true

require 'rails_helper'

RSpec.describe DataMigrations::RepairHandoffTracksJob, type: :job do
  include ActiveSupport::Testing::TimeHelpers

  let(:two_trackers) { create(:user) }
  let(:one_tracker) { create(:user) }
  let(:two_trackers_long_ago) { create(:user) }
  let(:inactive_two_trackers) { create(:user).tap { |user| user.update_column(:status, :inactive) } }

  before do
    [two_trackers, inactive_two_trackers].each do |user|
      create(:track, user:, tracker_id: 'phone', start_at: 2.months.ago, end_at: 2.months.ago + 1.hour)
      create(:track, user:, tracker_id: 'watch', start_at: 1.month.ago, end_at: 1.month.ago + 1.hour)
    end
    create(:track, user: one_tracker, tracker_id: 'phone', start_at: 2.months.ago, end_at: 2.months.ago + 1.hour)
    create(:track, user: one_tracker, tracker_id: 'phone', start_at: 1.month.ago, end_at: 1.month.ago + 1.hour)
    create(:track, user: two_trackers_long_ago, tracker_id: 'phone', start_at: 2.years.ago,
                   end_at: 2.years.ago + 1.hour)
    create(:track, user: two_trackers_long_ago, tracker_id: nil, start_at: 1.month.ago,
                   end_at: 1.month.ago + 1.hour)
  end

  it 'repairs the last twelve months of active users who record with more than one tracker' do
    freeze_time do
      described_class.perform_now

      expect(Tracks::HandoffRepairJob).to have_been_enqueued.with(two_trackers.id, 12.months.ago.to_i).exactly(:once)
      expect(enqueued_jobs.count { |job| job['job_class'] == 'Tracks::HandoffRepairJob' }).to eq(1)
    end
  end

  it 'spreads the repairs over the next hour' do
    freeze_time do
      described_class.perform_now

      job = enqueued_jobs.find { |enqueued| enqueued['job_class'] == 'Tracks::HandoffRepairJob' }
      expect(Time.zone.parse(job['scheduled_at'])).to be_between(Time.current, 1.hour.from_now)
    end
  end
end
