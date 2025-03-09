# frozen_string_literal: true

module Visits
  class TimeChunks
    def initialize(start_at:, end_at:)
      @start_at = start_at
      @end_at = end_at
      @time_chunks = []
    end

    def call
      # If the start date is in the future or equal to the end date,
      # handle as a special case extending to the end of the start's year
      if start_at >= end_at
        year_end = start_at.end_of_year
        return [start_at...year_end]
      end

      # Special case for dates within the same year
      if start_at.year == end_at.year
        year_end = start_at.end_of_year
        return [start_at...year_end]
      end

      # First chunk: from start_at to end of that year
      first_end = start_at.end_of_year
      time_chunks << (start_at...first_end)

      # Full-year chunks
      current = first_end.beginning_of_year + 1.year # Start from the next full year
      while current.year < end_at.year
        year_end = current.end_of_year
        time_chunks << (current...year_end)
        current += 1.year
      end

      # Last chunk: from start of the last year to end_at
      time_chunks << (current...end_at) if current.year == end_at.year

      time_chunks
    end

    private

    attr_reader :start_at, :end_at, :time_chunks
  end
end
