# frozen_string_literal: true

class ValidateCascadingTrackSegmentForeignKey < ActiveRecord::Migration[8.0]
  def up
    validate_foreign_key :track_segments, :tracks
  end

  def down; end
end
