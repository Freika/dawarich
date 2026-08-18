# frozen_string_literal: true

require 'rails_helper'

RSpec.describe DataMigrations::AddPointDimensionColumnsJob, type: :job do
  before { allow(DawarichSettings).to receive(:self_hosted?).and_return(true) }

  describe '#perform' do
    # The columns already exist in the loaded schema, which is the state this
    # job is designed to tolerate: it is the boot migration's fallback and may
    # run after the ALTER has already landed.
    it 'starts the backfill once the columns are in place' do
      expect { described_class.perform_now }.to \
        have_enqueued_job(DataMigrations::BackfillPointDimensionsJob)
    end

    # The columns exist in the loaded schema, so this is the only example that
    # reaches the ALTER at all. Dropping them here is safe: the surrounding
    # example transaction rolls the DDL back, and the column cache is reset
    # either way so no later example sees the gap.
    it 'adds the columns when the boot migration could not' do
      connection = ActiveRecord::Base.connection
      connection.execute('ALTER TABLE points DROP COLUMN source_id, DROP COLUMN motion_id')
      Point.reset_column_information
      expect(connection.column_exists?(:points, :source_id)).to be false

      described_class.perform_now

      expect(connection.column_exists?(:points, :source_id)).to be true
      expect(connection.column_exists?(:points, :motion_id)).to be true
    ensure
      Point.reset_column_information
    end

    it 'leaves existing columns alone instead of re-running the ALTER' do
      expect(ActiveRecord::Base.connection).not_to receive(:execute)

      described_class.perform_now
    end

    it 'does not start the backfill while the columns are still missing' do
      allow_any_instance_of(described_class).to receive(:columns_present?).and_return(false)
      allow_any_instance_of(described_class).to receive(:add_columns)

      expect { described_class.perform_now }.not_to \
        have_enqueued_job(DataMigrations::BackfillPointDimensionsJob)
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
      expect(described_class.rescue_handlers.map(&:first))
        .to include('ActiveRecord::LockWaitTimeout', 'ActiveRecord::QueryAborted')
    end
  end
end
