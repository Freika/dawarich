# frozen_string_literal: true

require 'rails_helper'
require Rails.root.join('db/migrate/20260726213000_cascade_track_segment_deletes')
require Rails.root.join('db/migrate/20260726213100_validate_cascading_track_segment_foreign_key')

RSpec.describe CascadeTrackSegmentDeletes do
  subject(:migration) { described_class.new }

  it 'retries the atomic foreign-key swap when the DDL lock is unavailable' do
    attempts = 0
    allow(migration).to receive(:transaction).and_yield
    allow(migration.connection).to receive(:execute)
    allow(migration).to receive(:sleep)
    allow(migration).to receive(:remove_foreign_key) do
      attempts += 1
      raise ActiveRecord::LockWaitTimeout, 'lock timeout' if attempts == 1
      raise ActiveRecord::Deadlocked, 'deadlock' if attempts == 2
    end
    allow(migration).to receive(:add_foreign_key)

    migration.up

    expect(attempts).to eq(3)
    expect(migration).to have_received(:sleep).twice
    expect(migration.connection).to have_received(:execute)
      .with("SET LOCAL lock_timeout = '#{described_class::LOCK_TIMEOUT}'").exactly(3).times
    expect(migration).to have_received(:add_foreign_key)
      .with(:track_segments, :tracks, on_delete: :cascade, validate: false).once
  end
end

RSpec.describe ValidateCascadingTrackSegmentForeignKey do
  subject(:migration) { described_class.new }

  it 'retries validation when the DDL lock is unavailable' do
    attempts = 0
    allow(migration).to receive(:transaction).and_yield
    allow(migration.connection).to receive(:execute)
    allow(migration).to receive(:sleep)
    allow(migration).to receive(:validate_foreign_key) do
      attempts += 1
      raise ActiveRecord::LockWaitTimeout, 'lock timeout' if attempts == 1
      raise ActiveRecord::Deadlocked, 'deadlock' if attempts == 2
    end

    migration.up

    expect(attempts).to eq(3)
    expect(migration).to have_received(:sleep).twice
    expect(migration.connection).to have_received(:execute)
      .with("SET LOCAL lock_timeout = '#{described_class::LOCK_TIMEOUT}'").exactly(3).times
  end
end
