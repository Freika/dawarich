# frozen_string_literal: true

module Tracks
  module KeptTracks
    def self.condition
      tracks = Track.arel_table
      tracks[:import_id].not_eq(nil).or(TrackSegment.outranking_inference_on(tracks[:id]))
    end
  end
end
