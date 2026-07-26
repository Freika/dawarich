# frozen_string_literal: true

class CascadeTrackSegmentDeletes < ActiveRecord::Migration[8.0]
  def up
    remove_foreign_key :track_segments, :tracks
    add_foreign_key :track_segments, :tracks, on_delete: :cascade, validate: false
  end

  def down
    remove_foreign_key :track_segments, :tracks
    add_foreign_key :track_segments, :tracks
  end
end
