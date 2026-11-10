# frozen_string_literal: true

class AddDetectionToTrips < ActiveRecord::Migration[8.0]
  def change
    add_column :trips, :origin, :integer, null: false, default: 0
    add_column :trips, :user_edited_at, :datetime

    create_table :trip_detection_dismissals do |t|
      t.references :user, null: false, foreign_key: { on_delete: :cascade }
      t.datetime :started_at, null: false
      t.datetime :ended_at, null: false

      t.timestamps
    end
  end
end
