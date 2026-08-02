# frozen_string_literal: true

require 'rails_helper'

RSpec.describe DataMigrations::RecalculateAnomaliesUserJob, type: :job do
  let(:user) { create(:user) }

  let!(:wrongly_flagged) do
    create(:point, user: user, accuracy: 60, anomaly: true,
                   timestamp: 30.minutes.ago.to_i,
                   latitude: 52.52, longitude: 13.405,
                   lonlat: 'POINT(13.405 52.52)')
  end

  def chunk_jobs
    ActiveJob::Base.queue_adapter.enqueued_jobs.select { |job| job[:job] == Tracks::TimeChunkProcessorJob }
  end

  it 'runs on a queue that yields to live traffic' do
    expect(described_class.new.queue_name).to eq('low_priority')
  end

  it 're-evaluates the points against the current noise rules' do
    described_class.perform_now(user.id)

    expect(wrongly_flagged.reload.anomaly).not_to be true
  end

  it 'rebuilds tracks, stats and digests without notifying the user' do
    described_class.perform_now(user.id)

    expect(chunk_jobs).not_to be_empty
    expect(user.notifications.where(title: 'Data recalculation completed')).not_to exist
  end

  it 'rebuilds on its own queue instead of handing the work to :stats' do
    described_class.perform_now(user.id)

    expect(Users::RecalculateDataJob).not_to have_been_enqueued
  end

  it 'keeps the track rebuild off :tracks, where live tracking runs' do
    described_class.perform_now(user.id)

    expect(chunk_jobs.map { |job| job[:queue] }.uniq).to eq(['low_priority'])
  end

  it 'retries on the bounded path instead of stamping when the track lock is busy' do
    allow(Tracks::PerUserLock).to receive(:with_user_lock).and_raise(Tracks::PerUserLock::AcquisitionTimeout)

    expect do
      described_class.perform_now(user.id)
    end.to have_enqueued_job(described_class).with(user.id, attempt: 2)

    expect(user.reload.settings[described_class::RECALCULATED_SETTINGS_KEY]).to be_nil
  end

  it 'gives up on a busy track lock at the same cap as a busy backfill lock' do
    allow(Tracks::PerUserLock).to receive(:with_user_lock).and_raise(Tracks::PerUserLock::AcquisitionTimeout)

    expect do
      described_class.perform_now(user.id, attempt: described_class::MAX_LOCK_ATTEMPTS)
    end.not_to have_enqueued_job(described_class)

    expect(user.reload.settings[described_class::RECALCULATED_SETTINGS_KEY]).to be_nil
  end

  it 'leaves the user unstamped when the rebuild fails, so a re-run picks them up' do
    allow(Tracks::PerUserLock).to receive(:with_user_lock).and_raise(StandardError, 'rebuild failed')

    described_class.perform_now(user.id)

    expect(user.reload.settings[described_class::RECALCULATED_SETTINGS_KEY]).to be_nil
  end

  it 'retries a failing rebuild a bounded number of times rather than Sidekiq default' do
    allow(Tracks::PerUserLock).to receive(:with_user_lock).and_raise(StandardError, 'rebuild failed')

    expect do
      described_class.perform_now(user.id)
    end.to have_enqueued_job(described_class)
  end

  it 'hands the slot back once a failing rebuild exhausts its attempts' do
    allow(Tracks::PerUserLock).to receive(:with_user_lock).and_raise(StandardError, 'rebuild failed')

    job = described_class.new(user.id)
    job.exception_executions = { '[StandardError]' => described_class::MAX_REBUILD_ATTEMPTS }

    expect { job.perform_now }.to have_enqueued_job(DataMigrations::RecalculateAnomaliesJob).with(limit: 1)
  end

  it 'records that the user has been recalculated' do
    described_class.perform_now(user.id)

    expect(user.reload.settings[described_class::RECALCULATED_SETTINGS_KEY]).to be_present
  end

  it 'keeps the rest of the settings intact while recording it' do
    user.update!(settings: user.settings.merge('gps_filtering_enabled' => true, 'maps' => { 'distance_unit' => 'km' }))

    described_class.perform_now(user.id)

    expect(user.reload.settings).to include('maps' => { 'distance_unit' => 'km' })
  end

  it 'does nothing on a second run' do
    described_class.perform_now(user.id)
    after_first_run = chunk_jobs.size

    described_class.perform_now(user.id)

    expect(chunk_jobs.size).to eq(after_first_run)
  end

  it 'leaves users who turned GPS filtering off untouched' do
    user.update!(settings: user.settings.merge('gps_filtering_enabled' => false))

    described_class.perform_now(user.id)

    expect(wrongly_flagged.reload.anomaly).to be true
    expect(chunk_jobs).to be_empty
  end

  it 'retries later instead of marking the user done when another backfill holds the lock' do
    allow(Points::AnomalyBackfillUserJob).to receive(:perform_now).and_return(false)

    expect do
      described_class.perform_now(user.id)
    end.to have_enqueued_job(described_class).with(user.id, attempt: 2)

    expect(user.reload.settings[described_class::RECALCULATED_SETTINGS_KEY]).to be_nil
  end

  it 'gives up instead of retrying forever when the lock is never released' do
    allow(Points::AnomalyBackfillUserJob).to receive(:perform_now).and_return(false)

    expect do
      described_class.perform_now(user.id, attempt: described_class::MAX_LOCK_ATTEMPTS)
    end.not_to have_enqueued_job(described_class)
  end

  it 'hands its slot back when it finishes, so the next user starts' do
    expect do
      described_class.perform_now(user.id)
    end.to have_enqueued_job(DataMigrations::RecalculateAnomaliesJob).with(limit: 1)
  end

  it 'hands its slot back when it gives up on a stuck lock' do
    allow(Points::AnomalyBackfillUserJob).to receive(:perform_now).and_return(false)

    expect do
      described_class.perform_now(user.id, attempt: described_class::MAX_LOCK_ATTEMPTS)
    end.to have_enqueued_job(DataMigrations::RecalculateAnomaliesJob).with(limit: 1)
  end

  it 'keeps its slot while it is waiting on a busy lock' do
    allow(Points::AnomalyBackfillUserJob).to receive(:perform_now).and_return(false)

    expect do
      described_class.perform_now(user.id)
    end.not_to have_enqueued_job(DataMigrations::RecalculateAnomaliesJob)
  end

  it 'ignores a user that has since been deleted' do
    deleted_id = user.id
    user.destroy!

    expect { described_class.perform_now(deleted_id) }.not_to raise_error
  end
end
