# frozen_string_literal: true

module Posters
  class TrackBuilder
    GAP_SECONDS = 1.hour.to_i

    def initialize(user:, start_at:, end_at:)
      @user = user
      @start_at = start_at
      @end_at = end_at
    end

    def call
      rows = fetch_rows
      return nil if rows.empty?

      segments = split_on_gaps(rows)
      return nil if segments.empty?

      {
        'type' => 'MultiLineString',
        'coordinates' => segments.map { |segment| segment.map { |row| [row[0], row[1]] } }
      }
    end

    private

    def fetch_rows
      @user.points
           .not_anomaly
           .where(timestamp: @start_at.to_i..@end_at.to_i)
           .order(timestamp: :asc)
           .pluck(Arel.sql('ST_X(lonlat::geometry)'), Arel.sql('ST_Y(lonlat::geometry)'), :timestamp)
    end

    def split_on_gaps(rows)
      segments = []
      current = [rows.first]

      rows.each_cons(2) do |previous, row|
        if row[2] - previous[2] > GAP_SECONDS
          segments << current
          current = []
        end
        current << row
      end
      segments << current

      segments.select { |segment| segment.size >= 2 }
    end
  end
end
