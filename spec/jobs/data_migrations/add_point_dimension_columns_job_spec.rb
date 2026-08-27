# frozen_string_literal: true

require 'rails_helper'

RSpec.describe DataMigrations::AddPointDimensionColumnsJob, type: :job do
  before { allow(DawarichSettings).to receive(:self_hosted?).and_return(true) }

  describe '#perform' do
    # The column already exists in the loaded schema, which is the state this
    # job is designed to tolerate: it is the boot migration's fallback and may
    # run after the ALTER has already landed.
    it 'starts the backfill once the column is in place' do
      expect { described_class.perform_now }.to \
        have_enqueued_job(DataMigrations::BackfillPointDimensionsJob)
    end

    # The column exists in the loaded schema, so this is the only example that
    # reaches the ALTER at all. Dropping them here is safe: the surrounding
    # example transaction rolls the DDL back, and the column cache is reset
    # either way so no later example sees the gap.
    it 'adds the column when the boot migration could not' do
      connection = ActiveRecord::Base.connection
      connection.execute('ALTER TABLE points DROP COLUMN source_id')
      Point.reset_column_information
      expect(connection.column_exists?(:points, :source_id)).to be false

      described_class.perform_now

      expect(connection.column_exists?(:points, :source_id)).to be true
    ensure
      Point.reset_column_information
    end

    it 'leaves an existing column alone instead of re-running the ALTER' do
      expect(ActiveRecord::Base.connection).not_to receive(:execute)

      described_class.perform_now
    end

    it 'does not start the backfill while the column is still missing' do
      connection = ActiveRecord::Base.connection
      connection.execute('ALTER TABLE points DROP COLUMN source_id')
      Point.reset_column_information
      allow(connection).to receive(:execute).and_call_original
      allow(connection).to receive(:execute)
        .with(/ADD COLUMN IF NOT EXISTS source_id/).and_return(nil)

      expect { described_class.perform_now }.not_to \
        have_enqueued_job(DataMigrations::BackfillPointDimensionsJob)
    ensure
      Point.reset_column_information
    end

    it 'adds the columns on Cloud but leaves the backfill for a chosen window' do
      allow(DawarichSettings).to receive(:self_hosted?).and_return(false)

      expect { described_class.perform_now }.not_to \
        have_enqueued_job(DataMigrations::BackfillPointDimensionsJob)
    end

    it 'honours the opt-out variable on the deferred path too' do
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with('SKIP_POINT_DIMENSION_BACKFILL').and_return('1')

      expect { described_class.perform_now }.not_to \
        have_enqueued_job(DataMigrations::BackfillPointDimensionsJob)
    end

    it 'retries rather than giving up the first time it loses the lock' do
      allow_any_instance_of(described_class).to receive(:column_present?).and_return(false)
      allow_any_instance_of(described_class).to receive(:add_column)
        .and_raise(ActiveRecord::LockWaitTimeout)

      expect { described_class.perform_now }.to have_enqueued_job(described_class)
    end

    it 'gives the operator both manual steps when it gives up' do
      allow(Rails.logger).to receive(:error)

      described_class.log_exhaustion(ActiveRecord::LockWaitTimeout.new('lock'))

      expect(Rails.logger).to have_received(:error)
        .with(/ALTER TABLE points.*BackfillPointDimensionsJob\.perform_later/)
    end

    it 'retries an aborted attempt the same way' do
      allow_any_instance_of(described_class).to receive(:column_present?).and_return(false)
      allow_any_instance_of(described_class).to receive(:add_column)
        .and_raise(ActiveRecord::QueryCanceled)

      expect { described_class.perform_now }.to have_enqueued_job(described_class)
    end
  end
end
