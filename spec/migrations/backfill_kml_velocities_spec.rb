# frozen_string_literal: true

require 'rails_helper'
require Rails.root.join('db/migrate/20261026000000_backfill_kml_velocities.rb')

RSpec.describe BackfillKmlVelocities do
  subject(:migration) { described_class.new }

  before { allow(DawarichSettings).to receive(:self_hosted?).and_return(true) }

  it 'does not start the backfill on Dawarich Cloud' do
    allow(DawarichSettings).to receive(:self_hosted?).and_return(false)

    expect { migration.up }.not_to have_enqueued_job(DataMigrations::BackfillMissingVelocitiesJob)
  end

  it 'honours the opt-out variable' do
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with('SKIP_POINT_DIMENSION_BACKFILL').and_return('1')

    expect { migration.up }.not_to have_enqueued_job(DataMigrations::BackfillMissingVelocitiesJob)
  end

  it 'queues the shared velocity backfill for points imported without speeds' do
    expect { migration.up }.to have_enqueued_job(DataMigrations::BackfillMissingVelocitiesJob)
  end

  it 'queues the backfill on a rerun after the job queue was unreachable' do
    allow(DataMigrations::BackfillMissingVelocitiesJob)
      .to receive(:perform_later).and_raise(StandardError, 'Connection refused')
    expect { migration.up }.not_to raise_error
    allow(DataMigrations::BackfillMissingVelocitiesJob).to receive(:perform_later).and_call_original

    expect { described_class.new.up }.to have_enqueued_job(DataMigrations::BackfillMissingVelocitiesJob)
  end

  it 'does not queue a second backfill when replayed' do
    2.times { described_class.new.up }

    expect(enqueued_jobs.count { |job| job[:job] == DataMigrations::BackfillMissingVelocitiesJob }).to eq(1)
  end
end
