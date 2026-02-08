# frozen_string_literal: true

class CreateNotesAndRenameTripsRichText < ActiveRecord::Migration[8.0]
  def up
    create_table :notes do |t|
      t.references :user, null: false, foreign_key: true
      t.string     :title
      t.st_point   :lonlat, geographic: true
      t.string     :attachable_type
      t.bigint     :attachable_id
      t.datetime   :noted_at
      t.timestamps
    end

    add_index :notes, %i[attachable_type attachable_id]
    add_index :notes, :lonlat, using: :gist
    add_index :notes, %i[user_id noted_at]

    execute <<-SQL.squish
      CREATE UNIQUE INDEX index_notes_on_attachable_and_noted_date
      ON notes (attachable_type, attachable_id, (CAST(noted_at AS date)))
      WHERE attachable_id IS NOT NULL
    SQL

    # Rename Trip's has_rich_text :notes to :description
    execute <<-SQL.squish
      UPDATE action_text_rich_texts
      SET name = 'description'
      WHERE record_type = 'Trip' AND name = 'notes'
    SQL
  end

  def down
    execute <<-SQL.squish
      UPDATE action_text_rich_texts
      SET name = 'notes'
      WHERE record_type = 'Trip' AND name = 'description'
    SQL

    drop_table :notes
  end
end
