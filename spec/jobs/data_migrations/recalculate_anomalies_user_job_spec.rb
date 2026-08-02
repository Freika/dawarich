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

  before { allow(Users::RecalculateDataJob).to receive(:perform_now).and_call_original }

  it 'runs on a queue that yields to live traffic' do
    expect(described_class.new.queue_name).to eq('low_priority')
  end

  it 're-evaluates the points against the current noise rules' do
    described_class.perform_now(user.id)

    expect(wrongly_flagged.reload.anomaly).not_to be true
  end

  it 'rebuilds tracks, stats and digests without notifying the user' do
    described_class.perform_now(user.id)

    expect(Users::RecalculateDataJob).to have_received(:perform_now).with(user.id, notify: false)
  end

  it 'rebuilds on its own queue instead of handing the work to :stats' do
    described_class.perform_now(user.id)

    expect(Users::RecalculateDataJob).not_to have_been_enqueued
  end

  it 'leaves the user unstamped when the rebuild fails, so a re-run picks them up' do
    allow(Users::RecalculateDataJob).to receive(:perform_now).and_raise(StandardError, 'rebuild failed')

    expect { described_class.perform_now(user.id) }.to raise_error(StandardError)

    expect(user.reload.settings[described_class::RECALCULATED_SETTINGS_KEY]).to be_nil
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

    described_class.perform_now(user.id)

    expect(Users::RecalculateDataJob).to have_received(:perform_now).once
  end

  it 'leaves users who turned GPS filtering off untouched' do
    user.update!(settings: user.settings.merge('gps_filtering_enabled' => false))

    described_class.perform_now(user.id)

    expect(wrongly_flagged.reload.anomaly).to be true
    expect(Users::RecalculateDataJob).not_to have_received(:perform_now)
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

  it 'ignores a user that has since been deleted' do
    deleted_id = user.id
    user.destroy!

    expect { described_class.perform_now(deleted_id) }.not_to raise_error
  end
end
