# frozen_string_literal: true

module Timeline
  module TrackDayShares
    module_function

    def shares_for(track, timezone)
      tz = timezone.presence || 'UTC'
      start_local = track.start_at.in_time_zone(tz)
      end_local = track.end_at.in_time_zone(tz)

      total = (end_local - start_local).to_f
      return { start_local.to_date => 1.0 } if total <= 0

      shares = {}
      cursor = start_local
      while cursor < end_local
        boundary = [cursor.beginning_of_day + 1.day, end_local].min
        shares[cursor.to_date] = (boundary - cursor).to_f / total
        cursor = boundary
      end
      shares
    end
  end
end
