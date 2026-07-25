# frozen_string_literal: true

class AddPointsTrackForeignKey < ActiveRecord::Migration[8.0]
  # Adds protection for new writes/deletes without scanning historic points.
  # A later migration can validate after dangling legacy track references are remediated.
  def up
    add_foreign_key :points, :tracks, column: :track_id, on_delete: :restrict, validate: false
  end

  def down
    remove_foreign_key :points, :tracks, column: :track_id, if_exists: true
  end
end
