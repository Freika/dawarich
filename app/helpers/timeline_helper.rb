# frozen_string_literal: true

module TimelineHelper
  WEEKDAY_HEADER_LABELS = %w[M T W T F S S].freeze

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

  # Hash-entry helpers (Timeline::DayAssembler returns hash-shaped entries).
  # These intentionally mirror the Visit-object helpers above but operate on
  # the serialized hash payload, avoiding per-row Visit.find (N+1).

  def visit_entry_display_name(entry)
    entry[:name].presence || entry[:place]&.dig(:name).presence || 'Unnamed'
  end

  # Duration-based heuristic for hash entries. Avoids N+1 Visit lookups.
  def visit_entry_all_day?(entry)
    times = visit_entry_times(entry)
    duration_minutes = entry[:duration].to_i
    return true if duration_minutes >= 23 * 60

    times[:start_at].hour.zero? && (times[:ended_at] - times[:start_at]) >= 23.hours
  end

  def visit_entry_times(entry)
    started = Time.zone.parse(entry[:started_at].to_s)
    ended = Time.zone.parse(entry[:ended_at].to_s)
    {
      start_at: started,
      ended_at: ended,
      start_label: started.strftime('%H:%M'),
      end_label: ended.strftime('%H:%M')
    }
  end

  def visit_entry_status(entry)
    entry[:status].presence || 'confirmed'
  end

  def day_label(day)
    Date.parse(day[:date].to_s).strftime('%A, %B %-d')
  end

  def day_total_visits_count(day)
    s = day[:summary] || {}
    s[:confirmed_count].to_i + s[:suggested_count].to_i + s[:declined_count].to_i
  end

  def day_bounds_json(day)
    day[:bounds]&.to_json
  end

  def calendar_month_nav(summary)
    month_date = Date.parse("#{summary[:month]}-01")
    {
      prev: (month_date - 1.month).strftime('%Y-%m'),
      next: (month_date + 1.month).strftime('%Y-%m'),
      title: month_date.strftime('%B %Y')
    }
  end

  def calendar_weekday_labels
    WEEKDAY_HEADER_LABELS
  end

  def calendar_day_number(cell)
    Date.parse(cell[:date].to_s).day
  end

  # Returns the space-joined CSS class string for a calendar cell.
  # Uses Timeline::MonthSummary.heat_bucket (service-layer authoritative
  # bucketing with 6-level thresholds), not the simpler TimelineHelper
  # #heat_bucket which is kept for non-calendar contexts.
  def calendar_cell_classes(cell)
    bucket = Timeline::MonthSummary.heat_bucket(cell[:tracked_seconds])
    classes = ['cal-cell', "heat-#{bucket}"]
    classes << 'has-suggestions' if cell[:suggested_count].to_i.positive?
    classes << 'out-of-month' unless cell[:in_month]
    classes << 'disabled' if cell[:disabled]
    classes << (bucket >= 3 ? 'cal-cell--light-text' : 'cal-cell--dark-text')
    classes.join(' ')
  end
end
