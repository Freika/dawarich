# frozen_string_literal: true

module TimelineHelper
  # visit.duration is MINUTES.
  # Returns true when the visit covers (effectively) a whole day.
  def timeline_all_day?(visit)
    return false unless visit
    return true if visit.duration.to_i >= 23 * 60

    visit.started_at.hour.zero? && (visit.ended_at - visit.started_at) >= 23.hours
  end

  # minutes -> "Xh Ym" (or "Xm" when < 1h)
  def format_dwell_minutes(minutes)
    minutes = minutes.to_i
    return '0m' if minutes <= 0

    h = minutes / 60
    m = minutes % 60
    return "#{h}h" if m.zero? && h.positive?
    return "#{m}m" if h.zero?

    "#{h}h #{m}m"
  end

  # Tracked seconds -> bucket index 0..5
  def heat_bucket(tracked_seconds)
    s = tracked_seconds.to_i
    return 0 if s <= 0

    h = s / 3600.0
    return 1 if h < 2
    return 2 if h < 4
    return 3 if h < 8
    return 4 if h < 12

    5
  end
end
