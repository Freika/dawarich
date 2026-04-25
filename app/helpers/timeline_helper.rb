# frozen_string_literal: true

module TimelineHelper
  WEEKDAY_HEADER_LABELS = %w[M T W T F S S].freeze

  # Max suggested-place candidates shown before the "Show N more" disclosure
  # kicks in. The assembler dedupes by name upstream; this just keeps the
  # visible picker compact regardless of geocoder quality.
  SUGGESTED_PICKER_VISIBLE_LIMIT = 3

  # "YYYY-MM" for the calendar's initial month. Prefers, in order:
  #   1. `params[:date]` (the selected day, e.g. "2025-12-11")
  #   2. `params[:start_at]` (range start, e.g. "2025-12-11T00:00:00")
  #   3. Today in the user's timezone
  # Edge case avoided: around UTC midnight, plain Date.current returns the
  # server-local day, which can differ from the user's day by one.
  def initial_calendar_month(user)
    date_param = params[:date].presence || params[:start_at].presence
    parsed = parse_calendar_date(date_param)
    return parsed.strftime('%Y-%m') if parsed

    tz = user&.safe_settings&.timezone.presence || 'UTC'
    Time.use_zone(tz) { Date.current.strftime('%Y-%m') }
  end

  def parse_calendar_date(value)
    return nil if value.blank?

    Date.parse(value)
  rescue ArgumentError, TypeError
    nil
  end

  # Lower-cased, space-joined string of all tokens a user might type into the
  # rail's search box to find this visit. Baked into the row as
  # `data-search-tokens` so the Stimulus filter is a single substring check.
  def visit_entry_search_tokens(entry)
    [
      entry[:name],
      entry[:editable_name],
      entry.dig(:place, :name),
      entry.dig(:place, :city),
      entry.dig(:place, :country),
      entry.dig(:area, :name),
      Array(entry[:tags]).map { |t| t[:name] }
    ].flatten.compact.join(' ').downcase
  end

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
    entry[:name].presence ||
      entry[:place]&.dig(:name).presence ||
      entry[:area]&.dig(:name).presence ||
      'Unnamed'
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

  # Splits suggested places into [visible, overflow] for the picker UI.
  # `visible` is rendered as selectable rows; `overflow` lives inside the
  # <details> disclosure so the default footprint stays compact.
  def split_suggested_places(places, limit: SUGGESTED_PICKER_VISIBLE_LIMIT)
    list = Array(places)
    return [list, []] if list.size <= limit

    [list.first(limit), list.drop(limit)]
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
  # Heat bucket is precomputed by Timeline::MonthSummary as a month-relative
  # grade (1..5 = quintiles of the busiest day in the visible month;
  # 0 = no activity at all).
  def calendar_cell_classes(cell)
    bucket = cell[:heat_bucket].to_i
    classes = ['cal-cell', "heat-#{bucket}"]
    classes << 'has-suggestions' if cell[:suggested_count].to_i.positive?
    classes << 'out-of-month' unless cell[:in_month]
    classes << 'disabled' if cell[:disabled]
    classes << (bucket >= 3 ? 'cal-cell--light-text' : 'cal-cell--dark-text')
    classes.join(' ')
  end
end
