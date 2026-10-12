# frozen_string_literal: true

class EnqueueTrackSegmentTimeAnchorBackfill < ActiveRecord::Migration[8.0]
  def up
    TrackSegments::TimeAnchorBackfillJob.perform_later if defined?(TrackSegments::TimeAnchorBackfillJob)
  end

  def down; end
end
