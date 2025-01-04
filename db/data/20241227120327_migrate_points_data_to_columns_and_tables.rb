# frozen_string_literal: true

class MigratePointsDataToColumnsAndTables < ActiveRecord::Migration[8.0]
  def up
    points_ids = Point.pluck(:id).sort

    points_ids.each_slice(1000) do |slice|
      DataMigrations::MigratePointsDataToColumnsAndTablesJob.perform_later(slice)
    end
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end
end
