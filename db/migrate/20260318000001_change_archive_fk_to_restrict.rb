# frozen_string_literal: true

class ChangeArchiveFkToRestrict < ActiveRecord::Migration[8.0]
  # Both operations are metadata-only (no table scan) because validate: false.
  # Safe for large tables — no locks, no I/O.
  def up
    remove_foreign_key :points, :points_raw_data_archives,
                       column: :raw_data_archive_id, if_exists: true

    add_foreign_key :points, :points_raw_data_archives,
                    column: :raw_data_archive_id,
                    on_delete: :restrict,
                    validate: false
  end

  def down
    remove_foreign_key :points, :points_raw_data_archives,
                       column: :raw_data_archive_id, if_exists: true

    add_foreign_key :points, :points_raw_data_archives,
                    column: :raw_data_archive_id,
                    on_delete: :nullify,
                    validate: false
  end
end
