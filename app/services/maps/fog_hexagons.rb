# frozen_string_literal: true

module Maps
  class FogHexagons
    def initialize(user:, start_date:, end_date:)
      @user = user
      @start_date = start_date
      @end_date = end_date
    end

    def call
      indexes = collect_cell_ids
      {
        'h3_indexes' => indexes,
        'metadata' => { 'count' => indexes.size }
      }
    end

    private

    attr_reader :user, :start_date, :end_date

    def collect_cell_ids
      seen = Set.new

      stats_in_range.each do |stat|
        next unless stat.h3_hex_ids.is_a?(Array)

        stat.h3_hex_ids.each do |row|
          next unless row.is_a?(Array)

          h3_index, _count, earliest, latest = row
          next if h3_index.blank?
          next unless overlaps_range?(earliest, latest)

          seen << h3_index
        end
      end

      seen.to_a
    end

    def stats_in_range
      user.scoped_stats
          .where('(year * 100 + month) BETWEEN ? AND ?', month_key(start_date), month_key(end_date))
          .select(:id, :year, :month, :h3_hex_ids)
    end

    def month_key(time)
      (time.year * 100) + time.month
    end

    def overlaps_range?(earliest, latest)
      return true if earliest.blank? || latest.blank?

      earliest.to_i <= end_date.to_i && latest.to_i >= start_date.to_i
    end
  end
end
