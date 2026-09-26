# frozen_string_literal: true

module EnhancedImport
  class SourceSegmentsReset
    def initialize(import)
      @import = import
    end

    def call
      segments = TrackSegment.auto_classified.where(source: @import.source, track_id: annotated_tracks)
      track_ids = segments.distinct.pluck(:track_id)
      segments.delete_all
      ActiveJob.perform_all_later(track_ids.map { |id| TransportationModes::ReclassifyTrackJob.new(id) })
    end

    private

    def annotated_tracks
      Track.where(id: @import.points.where.not(track_id: nil).select(:track_id))
           .where('tracks.import_id IS DISTINCT FROM ?', @import.id)
           .select(:id)
    end
  end
end
