# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Anomaly migration interrupted mid-backfill', type: :job do
  let(:user) { create(:user, settings: { 'gps_filtering_enabled' => true }) }

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

  def january_cursor = Time.utc(2026, 1, 1).to_i

  it 'lets the interrupted backfill finish instead of scheduling a duplicate run' do
    interrupt_job_during_step(Points::AnomalyBackfillUserJob, :filter_months, cursor: january_cursor) do
      DataMigrations::RecalculateAnomaliesUserJob.new.perform(user.id)
    end

    expect(Points::AnomalyBackfillUserJob).to have_been_enqueued
    expect(DataMigrations::RecalculateAnomaliesUserJob).not_to have_been_enqueued
  end

  it 'does not stamp the user as recalculated while the backfill is still unfinished' do
    interrupt_job_during_step(Points::AnomalyBackfillUserJob, :filter_months, cursor: january_cursor) do
      DataMigrations::RecalculateAnomaliesUserJob.new.perform(user.id)
    end

    expect(user.reload.settings).not_to have_key('anomalies_recalculated_at')
  end

  it 'still treats a busy advisory lock as contention worth retrying' do
    allow(ActiveRecord::Base).to receive(:with_advisory_lock).and_return(false)

    DataMigrations::RecalculateAnomaliesUserJob.new.perform(user.id)

    expect(DataMigrations::RecalculateAnomaliesUserJob).to have_been_enqueued
  end
end
