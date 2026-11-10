# frozen_string_literal: true

class AddDetectionToTrips < ActiveRecord::Migration[8.0]
  def up
    add_column :trips, :origin, :integer, null: false, default: 0, if_not_exists: true
    add_column :trips, :user_edited_at, :datetime, if_not_exists: true

    create_table :trip_detection_dismissals, if_not_exists: true do |t|
      t.references :user, null: false, foreign_key: { on_delete: :cascade }
      t.datetime :started_at, null: false
      t.datetime :ended_at, null: false

      t.timestamps
    end
  end

  def down
    drop_table :trip_detection_dismissals, if_exists: true
    remove_column :trips, :user_edited_at, if_exists: true
    remove_column :trips, :origin, if_exists: true
  end
end
