# frozen_string_literal: true

class BackfillNotesColumns < ActiveRecord::Migration[8.0]
  def up
    return unless table_exists?(:notes)

    add_column :notes, :title, :string unless column_exists?(:notes, :title)
    add_column :notes, :body, :text unless column_exists?(:notes, :body)
    add_column :notes, :attachable_type, :string unless column_exists?(:notes, :attachable_type)
    add_column :notes, :attachable_id, :bigint unless column_exists?(:notes, :attachable_id)
    add_column :notes, :noted_at, :datetime unless column_exists?(:notes, :noted_at)
    add_column :notes, :lonlat, :st_point, geographic: true unless column_exists?(:notes, :lonlat)

    add_index :notes, %i[attachable_type attachable_id], if_not_exists: true
    add_index :notes, :lonlat, using: :gist, if_not_exists: true

    execute <<~SQL.squish
      CREATE UNIQUE INDEX IF NOT EXISTS index_notes_on_attachable_and_noted_date
      ON notes (attachable_type, attachable_id, (CAST(noted_at AS date)))
      WHERE attachable_id IS NOT NULL
    SQL
  end
end
