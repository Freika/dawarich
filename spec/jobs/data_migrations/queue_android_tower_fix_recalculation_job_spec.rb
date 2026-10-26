# frozen_string_literal: true

require 'rails_helper'

RSpec.describe DataMigrations::QueueAndroidTowerFixRecalculationJob do
  let(:queued_key) { DataMigrations::RecalculateAnomaliesUserJob::QUEUED_SETTINGS_KEY }
  let(:done_key) { DataMigrations::RecalculateAnomaliesUserJob::RECALCULATED_SETTINGS_KEY }
  let(:failed_key) { DataMigrations::RecalculateAnomaliesUserJob::FAILED_SETTINGS_KEY }
  let(:stamp_keys) { [queued_key, done_key, failed_key] }
  let(:recorded_at) { Time.utc(2026, 8, 6, 12).to_i }

  before { stub_const("#{described_class}::BATCH_SIZE", 1) }

  def user_with(stamps)
    user = create(:user)
    user.update!(settings: user.settings.merge(stamps))
    user
  end

  def swept_user
    user_with(queued_key => 1.week.ago.iso8601, done_key => 1.week.ago.iso8601)
  end

  def record_fix(user, accuracy:, vertical_accuracy:, timestamp: recorded_at)
    create(:point, user: user, accuracy: accuracy, vertical_accuracy: vertical_accuracy,
                   velocity: '0.0', timestamp: timestamp)
  end

  def run_chain
    perform_enqueued_jobs(only: described_class) { described_class.perform_later }
  end

  it 'reopens the anomaly sweep only for users with coarse Android fixes' do
    android_user = swept_user
    record_fix(android_user, accuracy: 1_200, vertical_accuracy: 0)
    failed_android_user = user_with(queued_key => 1.week.ago.iso8601, failed_key => 1.week.ago.iso8601)
    record_fix(failed_android_user, accuracy: 1_200, vertical_accuracy: 0)
    precise_android_user = swept_user
    record_fix(precise_android_user, accuracy: 15, vertical_accuracy: 0)
    ios_user = swept_user
    record_fix(ios_user, accuracy: 1_200, vertical_accuracy: -1)

    expect { run_chain }.to have_enqueued_job(DataMigrations::RecalculateAnomaliesJob).exactly(:once)

    expect(android_user.reload.settings.keys).not_to include(*stamp_keys)
    expect(failed_android_user.reload.settings.keys).not_to include(*stamp_keys)
    expect(precise_android_user.reload.settings.keys).to include(queued_key, done_key)
    expect(ios_user.reload.settings.keys).to include(queued_key, done_key)
  end

  it 'leaves coarse fixes recorded before the native Android uploader alone' do
    user = swept_user
    record_fix(user, accuracy: 1_200, vertical_accuracy: 0, timestamp: Time.utc(2025, 6, 1).to_i)

    run_chain

    expect(user.reload.settings.keys).to include(queued_key, done_key)
  end

  it 'does not take back a user whose recalculation is still running' do
    claim = 10.minutes.ago.iso8601
    user = user_with(queued_key => claim)
    record_fix(user, accuracy: 1_200, vertical_accuracy: 0)

    run_chain

    expect(user.reload.settings[queued_key]).to eq(claim)
  end
end
