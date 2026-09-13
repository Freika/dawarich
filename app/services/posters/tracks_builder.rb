# frozen_string_literal: true

module Posters
  class TracksBuilder
    def initialize(user:, start_at:, end_at:)
      @user = user
      @start_at = start_at
      @end_at = end_at
    end

    def call
      segments = fetch_segments
      return nil if segments.empty?

      {
        'type' => 'MultiLineString',
        'coordinates' => segments
      }
    end

    private

    def fetch_segments
      @user.tracks
           .where(start_at: ..@end_at, end_at: @start_at..)
           .order(start_at: :asc)
           .filter_map do |track|
             coordinates = track.original_path.points.map { |point| [point.x, point.y] }
             coordinates if coordinates.size >= 2
           end
    end
  end
end
