# frozen_string_literal: true

class DedupeTracksForUniqueIndex < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!

  def up
    DataMigrations::DedupeTracksForUniqueIndexJob.perform_now
  end

  def down
    # Data deletion is not reversible. Restore from backup if rollback is needed.
  end
end
