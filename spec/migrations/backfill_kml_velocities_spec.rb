# frozen_string_literal: true

require 'rails_helper'
require Rails.root.join('db/migrate/20261026000000_backfill_kml_velocities.rb')

RSpec.describe BackfillKmlVelocities do
  subject(:migration) { described_class.new }

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
