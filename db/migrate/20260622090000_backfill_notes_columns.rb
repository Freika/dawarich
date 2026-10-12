# frozen_string_literal: true

class BackfillNotesColumns < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!

  UNIQUE_INDEX_NAME = 'index_notes_on_attachable_and_noted_date'

  def up
    return unless table_exists?(:notes)

    add_column :notes, :title, :string unless column_exists?(:notes, :title)
    add_column :notes, :body, :text unless column_exists?(:notes, :body)
    add_column :notes, :attachable_type, :string unless column_exists?(:notes, :attachable_type)
    add_column :notes, :attachable_id, :bigint unless column_exists?(:notes, :attachable_id)
    add_column :notes, :noted_at, :datetime unless column_exists?(:notes, :noted_at)
    add_column :notes, :lonlat, :st_point, geographic: true unless column_exists?(:notes, :lonlat)

    add_index :notes, %i[attachable_type attachable_id], if_not_exists: true, algorithm: :concurrently
    add_index :notes, :lonlat, using: :gist, if_not_exists: true, algorithm: :concurrently

    return if index_name_exists?(:notes, UNIQUE_INDEX_NAME)

    ensure_no_duplicate_attachable_dates!

    execute <<~SQL.squish
      CREATE UNIQUE INDEX CONCURRENTLY IF NOT EXISTS #{UNIQUE_INDEX_NAME}
      ON notes (attachable_type, attachable_id, (CAST(noted_at AS date)))
      WHERE attachable_id IS NOT NULL
    SQL
  end

  private

  def ensure_no_duplicate_attachable_dates!
    duplicate_groups = select_all(<<~SQL.squish).to_a
      SELECT attachable_type, attachable_id, CAST(noted_at AS date) AS noted_date
      FROM notes
      WHERE attachable_id IS NOT NULL
      GROUP BY attachable_type, attachable_id, CAST(noted_at AS date)
      HAVING COUNT(*) > 1
    SQL

    return if duplicate_groups.empty?

    raise <<~MSG.squish
      Cannot create unique index #{UNIQUE_INDEX_NAME}: #{duplicate_groups.size} duplicate
      (attachable_type, attachable_id, noted_at::date) group(s) exist in the notes table.
      Resolve the duplicates and re-run this migration.
    MSG
  end
end
