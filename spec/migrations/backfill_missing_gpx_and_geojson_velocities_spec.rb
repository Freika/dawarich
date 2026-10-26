# frozen_string_literal: true

require 'rails_helper'
require Rails.root.join('db/migrate/20261026000000_backfill_kml_velocities.rb')
require Rails.root.join('db/migrate/20261026120000_backfill_missing_gpx_and_geojson_velocities.rb')

RSpec.describe BackfillMissingGpxAndGeojsonVelocities do
  subject(:migration) { described_class.new }

  it 'queues the velocity backfill for points imported without speeds' do
    expect { migration.up }.to have_enqueued_job(DataMigrations::BackfillMissingVelocitiesJob)
  end

  it 'does not queue a second backfill when replayed' do
    2.times { described_class.new.up }

    expect(enqueued_jobs.count { |job| job[:job] == DataMigrations::BackfillMissingVelocitiesJob }).to eq(1)
  end

  it 'queues the backfill on a rerun after the job queue was unreachable' do
    allow(DataMigrations::BackfillMissingVelocitiesJob)
      .to receive(:perform_later).and_raise(StandardError, 'Connection refused')
    expect { migration.up }.not_to raise_error
    allow(DataMigrations::BackfillMissingVelocitiesJob).to receive(:perform_later).and_call_original

    expect { described_class.new.up }.to have_enqueued_job(DataMigrations::BackfillMissingVelocitiesJob)
  end

  it 'queues one backfill when the KML migration runs first on a fresh install' do
    BackfillKmlVelocities.new.up
    migration.up

    expect(enqueued_jobs.count { |job| job[:job] == DataMigrations::BackfillMissingVelocitiesJob }).to eq(1)
  end

  it 'aborts on a missing constant instead of hiding a broken deploy' do
    allow(DataMigrations::BackfillMissingVelocitiesJob)
      .to receive(:perform_later).and_raise(NameError, 'uninitialized constant')

    expect { migration.up }.to raise_error(NameError)
  end
end
