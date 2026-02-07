# frozen_string_literal: true

class ReplaceTripDayNotesWithNotes < ActiveRecord::Migration[8.0]
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

    # Migrate TripDayNote data to Note
    execute <<-SQL.squish
      INSERT INTO notes (user_id, attachable_type, attachable_id, noted_at, created_at, updated_at)
      SELECT trips.user_id, 'Trip', trip_day_notes.trip_id,
             (trip_day_notes.date + interval '12 hours'), trip_day_notes.created_at, trip_day_notes.updated_at
      FROM trip_day_notes
      INNER JOIN trips ON trips.id = trip_day_notes.trip_id
    SQL

    # Migrate ActionText rich texts from TripDayNote to Note
    execute <<-SQL.squish
      UPDATE action_text_rich_texts
      SET record_type = 'Note',
          record_id = notes.id
      FROM notes
      INNER JOIN trip_day_notes ON trip_day_notes.trip_id = notes.attachable_id
        AND trip_day_notes.date = CAST(notes.noted_at AS date)
      WHERE action_text_rich_texts.record_type = 'TripDayNote'
        AND action_text_rich_texts.record_id = trip_day_notes.id
        AND action_text_rich_texts.name = 'body'
        AND notes.attachable_type = 'Trip'
    SQL

    # Rename Trip's has_rich_text :notes to :description
    execute <<-SQL.squish
      UPDATE action_text_rich_texts
      SET name = 'description'
      WHERE record_type = 'Trip' AND name = 'notes'
    SQL

    drop_table :trip_day_notes
  end

  def down
    create_table :trip_day_notes do |t|
      t.references :trip, null: false, foreign_key: true
      t.date :date, null: false

      t.timestamps
    end

    add_index :trip_day_notes, %i[trip_id date], unique: true

    # Migrate Note data back to TripDayNote
    execute <<-SQL.squish
      INSERT INTO trip_day_notes (trip_id, date, created_at, updated_at)
      SELECT attachable_id, CAST(noted_at AS date), created_at, updated_at
      FROM notes
      WHERE attachable_type = 'Trip' AND noted_at IS NOT NULL
    SQL

    # Migrate ActionText back
    execute <<-SQL.squish
      UPDATE action_text_rich_texts
      SET record_type = 'TripDayNote',
          record_id = trip_day_notes.id
      FROM trip_day_notes
      INNER JOIN notes ON notes.attachable_id = trip_day_notes.trip_id
        AND CAST(notes.noted_at AS date) = trip_day_notes.date
        AND notes.attachable_type = 'Trip'
      WHERE action_text_rich_texts.record_type = 'Note'
        AND action_text_rich_texts.record_id = notes.id
        AND action_text_rich_texts.name = 'body'
    SQL

    # Rename Trip's :description back to :notes
    execute <<-SQL.squish
      UPDATE action_text_rich_texts
      SET name = 'notes'
      WHERE record_type = 'Trip' AND name = 'description'
    SQL

    drop_table :notes
  end
end
