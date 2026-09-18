# frozen_string_literal: true

require 'rails_helper'
require Rails.root.join('db/migrate/20260907060000_enqueue_android_coarse_location_recalculation.rb')

RSpec.describe EnqueueAndroidCoarseLocationRecalculation do
  subject(:migration) { described_class.new }

  let(:queued_key) { DataMigrations::RecalculateAnomaliesUserJob::QUEUED_SETTINGS_KEY }
  let(:done_key) { DataMigrations::RecalculateAnomaliesUserJob::RECALCULATED_SETTINGS_KEY }
  let(:failed_key) { DataMigrations::RecalculateAnomaliesUserJob::FAILED_SETTINGS_KEY }

  it 'clears prior completion state and enqueues a fresh sweep' do
    user = create(:user)
    user.update!(settings: user.settings.merge(queued_key => 'queued', done_key => 'done', failed_key => 'failed'))

    expect { migration.up }.to have_enqueued_job(DataMigrations::RecalculateAnomaliesJob)
    expect(user.reload.settings.keys).not_to include(queued_key, done_key, failed_key)
  end

  it 'runs without a wrapping transaction' do
    expect(described_class.disable_ddl_transaction).to be true
  end

  it 'keeps deployment running when the queue is unavailable' do
    allow(DataMigrations::RecalculateAnomaliesJob).to receive(:perform_later).and_raise(StandardError, 'offline')

    expect { migration.up }.not_to raise_error
  end
end
