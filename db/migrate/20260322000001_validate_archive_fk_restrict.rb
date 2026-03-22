# frozen_string_literal: true

class ValidateArchiveFkRestrict < ActiveRecord::Migration[8.0]
  # Validates the existing FK added in 20260318000001.
  # Acquires SHARE UPDATE EXCLUSIVE lock (allows reads + writes, blocks only DDL).
  # Scans points table to confirm all raw_data_archive_id values are valid.
  def change
    validate_foreign_key :points, :points_raw_data_archives, column: :raw_data_archive_id
  end
end
