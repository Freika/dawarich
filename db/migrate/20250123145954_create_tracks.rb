# frozen_string_literal: true

class CreateTracks < ActiveRecord::Migration[8.0]
  def change
    create_table :tracks do |t|
      t.datetime :started_at, null: false
      t.datetime :ended_at, null: false
      t.references :user, null: false, foreign_key: true
      t.line_string :path, srid: 3857, null: false

      t.timestamps
    end
  end
end
