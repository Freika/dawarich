# frozen_string_literal: true

class RecalculateStatsAfterChangingDistanceUnits < ActiveRecord::Migration[8.0]
  def up
    BulkStatsCalculatingJob.perform_later
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end
end
