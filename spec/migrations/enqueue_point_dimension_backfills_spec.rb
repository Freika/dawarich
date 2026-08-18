# frozen_string_literal: true

require 'rails_helper'
require Rails.root.join('db/migrate/20260816150200_enqueue_point_dimension_backfills.rb')

RSpec.describe EnqueuePointDimensionBackfills do
  subject(:migration) { described_class.new }

  before { allow(DawarichSettings).to receive(:self_hosted?).and_return(true) }

  it 'hands the work to a background job instead of doing it inline' do
    expect { migration.up }.to have_enqueued_job(DataMigrations::BackfillPointDimensionsJob)
  end

  it 'leaves the country backfill to the dimensions job rather than racing it' do
    expect { migration.up }.not_to have_enqueued_job(DataMigrations::BackfillPointCountryIdJob)
  end

  it 'does not start the backfill on Dawarich Cloud' do
    allow(DawarichSettings).to receive(:self_hosted?).and_return(false)

    expect { migration.up }.not_to have_enqueued_job(DataMigrations::BackfillPointDimensionsJob)
  end

  it 'skips the backfill when the opt-out variable is set' do
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with('SKIP_POINT_DIMENSION_BACKFILL').and_return('1')

    expect { migration.up }.not_to have_enqueued_job(DataMigrations::BackfillPointDimensionsJob)
  end

  it 'defers to the columns job instead of stamping against missing columns' do
    allow(migration).to receive(:column_exists?).with(:points, :source_id).and_return(false)

    expect { migration.up }.to have_enqueued_job(DataMigrations::AddPointDimensionColumnsJob)
    expect(DataMigrations::BackfillPointDimensionsJob).not_to have_been_enqueued
  end

  # Both halves of the guard are asserted separately: checking only source_id
  # would let the migration drop the motion_id check without any example
  # noticing, and the backfill would then stamp against a missing column.
  it 'defers when only the motion column is missing' do
    allow(migration).to receive(:column_exists?).with(:points, :source_id).and_return(true)
    allow(migration).to receive(:column_exists?).with(:points, :motion_id).and_return(false)

    expect { migration.up }.to have_enqueued_job(DataMigrations::AddPointDimensionColumnsJob)
    expect(DataMigrations::BackfillPointDimensionsJob).not_to have_been_enqueued
  end

  # The columns must land even on Cloud; only the backfill is gated. The job
  # re-applies the same gate, so nothing starts backfilling behind our back.
  it 'still adds missing columns on Cloud even though the backfill is gated' do
    allow(DawarichSettings).to receive(:self_hosted?).and_return(false)
    allow(migration).to receive(:column_exists?).with(:points, :source_id).and_return(false)

    expect { migration.up }.to have_enqueued_job(DataMigrations::AddPointDimensionColumnsJob)
  end

  it 'does not abort the migration when the job queue is unreachable' do
    allow(DataMigrations::BackfillPointDimensionsJob)
      .to receive(:perform_later).and_raise(StandardError, 'Connection refused')

    expect { migration.up }.not_to raise_error
  end

  it 'aborts on a missing constant instead of hiding a broken deploy' do
    allow(DataMigrations::BackfillPointDimensionsJob)
      .to receive(:perform_later).and_raise(NameError, 'uninitialized constant')

    expect { migration.up }.to raise_error(NameError)
  end

  it 'logs how to start the backfill by hand when enqueueing failed' do
    allow(DataMigrations::BackfillPointDimensionsJob)
      .to receive(:perform_later).and_raise(StandardError, 'Connection refused')
    allow(Rails.logger).to receive(:error)

    migration.up

    expect(Rails.logger)
      .to have_received(:error).with(/DataMigrations::BackfillPointDimensionsJob\.perform_later/)
  end
end
