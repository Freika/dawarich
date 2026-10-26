# frozen_string_literal: true

require 'rails_helper'
require Rails.root.join('db/migrate/20261025220000_enqueue_handoff_track_repair.rb')
require Rails.root.join('db/migrate/20261025220100_enqueue_visits_redetection_for_paused_tracking.rb')

RSpec.describe 'Recalculations enqueued by the 1.18.0 upgrade' do
  it 'repairs tracks that bridge another tracker' do
    expect { EnqueueHandoffTrackRepair.new.up }.to have_enqueued_job(DataMigrations::RepairHandoffTracksJob)
  end

  it 're-runs visit detection for every user' do
    expect { EnqueueVisitsRedetectionForPausedTracking.new.up }.to have_enqueued_job(Visits::FleetRedetectJob)
  end

  it 'lets constrained installs skip the visit re-detection' do
    stub_const('ENV', ENV.to_h.merge('SKIP_VISITS_FLEET_REDETECT' => '1'))

    expect { EnqueueVisitsRedetectionForPausedTracking.new.up }.not_to have_enqueued_job(Visits::FleetRedetectJob)
  end
end
