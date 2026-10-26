# frozen_string_literal: true

require 'rails_helper'

RSpec.describe DataMigrations::QueueAndroidTowerFixRecalculationJob do
  let(:stamp_keys) do
    [
      DataMigrations::RecalculateAnomaliesUserJob::QUEUED_SETTINGS_KEY,
      DataMigrations::RecalculateAnomaliesUserJob::RECALCULATED_SETTINGS_KEY,
      DataMigrations::RecalculateAnomaliesUserJob::FAILED_SETTINGS_KEY
    ]
  end

  def swept_user
    user = create(:user)
    user.update!(settings: user.settings.merge(stamp_keys.index_with { 'stamped' }))
    user
  end

  def record_fix(user, accuracy:, vertical_accuracy:)
    create(:point, user: user, accuracy: accuracy, vertical_accuracy: vertical_accuracy, velocity: '0.0')
  end

  it 'reopens the anomaly sweep only for users with coarse Android fixes' do
    android_user = swept_user
    record_fix(android_user, accuracy: 1_200, vertical_accuracy: 0)
    precise_android_user = swept_user
    record_fix(precise_android_user, accuracy: 15, vertical_accuracy: 0)
    ios_user = swept_user
    record_fix(ios_user, accuracy: 1_200, vertical_accuracy: -1)

    expect { described_class.perform_now }.to have_enqueued_job(DataMigrations::RecalculateAnomaliesJob)

    expect(android_user.reload.settings.keys).not_to include(*stamp_keys)
    expect(precise_android_user.reload.settings.keys).to include(*stamp_keys)
    expect(ios_user.reload.settings.keys).to include(*stamp_keys)
  end
end
