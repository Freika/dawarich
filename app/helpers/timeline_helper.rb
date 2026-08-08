# frozen_string_literal: true

module TimelineHelper
  # Interior holes shorter than this are the ordinary seams between a visit
  # ending and the next track starting — real days are full of them, and
  # marking each one costs the marker its meaning. Detection v3 snaps visit
  # boundaries to movement edges, so the ragged 30–60 minute seams the old
  # detector produced are gone; what remains at 45+ minutes is genuinely
  # unrecorded time (a 79-minute dark dinner must earn its row).
  TIMELINE_GAP_MIN_MINUTES = 45

  # Ceiling on how far a long leg may stretch the rail, in px. Past this the
  # day column scrolls more than it communicates.
  JOURNEY_LEG_MAX_EXTRA_PX = 80

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
    return I18n.t('units.minutes_compact', value: 0) if minutes <= 0

    h = minutes / 60
    m = minutes % 60
    return I18n.t('units.hours_compact', value: h) if m.zero? && h.positive?
    return I18n.t('units.minutes_compact', value: m) if h.zero?

    I18n.t('units.hours_minutes_compact', hours: h, minutes: m)
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
      I18n.t('helpers.timeline.unnamed')
  end

  # Geocoders hand back one flat string — "Good Lood, Tadeusza Romanowicza, 4,
  # Krakow, Lesser Poland Voivodeship" — in which the only token a person
  # recognizes is the first. Split it so the row can print the recognizable
  # part loud and the rest as a quiet address line.
  def visit_entry_name_parts(entry)
    tokens = visit_entry_display_name(entry).split(',').map(&:strip).reject(&:blank?)
    return { primary: visit_entry_display_name(entry), secondary: nil } if tokens.empty?

    tokens = merge_house_numbers(tokens)
    primary = tokens.shift
    # The last token is the province / voivodeship / state — always the widest
    # and least useful unit. Drop it, unless it is the only context we have.
    tokens = tokens[0...-1] if tokens.length > 1

    { primary: primary, secondary: tokens.join(', ').presence }
  end

  # Walks the day's rows and calls out interior stretches nothing was recorded
  # for. Journeys overlap the visits that sort between their endpoints, so the
  # hole is measured against the furthest point already covered — diffing
  # consecutive rows would invent gaps inside a tracked drive.
  def timeline_entries_with_gaps(entries)
    covered_until = nil

    Array(entries).flat_map do |entry|
      started_at = Time.iso8601(entry[:started_at].to_s)
      ended_at = Time.iso8601(entry[:ended_at].to_s)
      gap_minutes = covered_until ? ((started_at - covered_until) / 60).floor : 0
      gap_start = covered_until
      covered_until = [covered_until, ended_at].compact.max

      next [entry] if gap_minutes < TIMELINE_GAP_MIN_MINUTES

      # Stamped with where the record stops rather than where it resumes —
      # that is the moment the user is being told about.
      [{ type: 'gap', minutes: gap_minutes, started_at: gap_start.iso8601 }, entry]
    end
  end

  # Extra px of rail a leg earns for its duration, so a three-hour drive
  # visibly outweighs a nine-minute hop. Square root, not linear: the day
  # needs to keep its proportions readable inside one scroll.
  def journey_leg_extra_height(seconds)
    minutes = seconds.to_i / 60
    return 0 if minutes <= 0

    (Math.sqrt(minutes) * 3.2).round.clamp(0, JOURNEY_LEG_MAX_EXTRA_PX)
  end

  # "Tadeusza Romanowicza", "4" arrives as two tokens because the geocoder
  # comma-separates the house number. Rejoin them with a space.
  def merge_house_numbers(tokens)
    tokens.each_with_object([]) do |token, merged|
      if merged.any? && token.match?(/\A\d+[a-z]?\z/i)
        merged[-1] = "#{merged.last} #{token}"
      else
        merged << token
      end
    end
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
      start_label: I18n.l(started, format: :hour_minute),
      end_label: I18n.l(ended, format: :hour_minute)
    }
  end

  def visit_entry_status(entry)
    entry[:status].presence || 'confirmed'
  end

  # Confidence gating applies only to machine suggestions — a visit the user
  # confirmed renders at full strength whatever the detector thought of it.
  # Rows without a score (legacy, pre-backfill) also render normally.
  def visit_entry_subdued?(entry)
    visit_entry_status(entry) != 'confirmed' && entry[:confidence_band] == :medium
  end

  def visit_entry_low_confidence?(entry)
    visit_entry_status(entry) != 'confirmed' && entry[:confidence_band] == :low
  end

  def day_label(day)
    I18n.l(Date.parse(day[:date].to_s), format: :weekday_month_day)
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
      title: I18n.l(month_date, format: :month_year)
    }
  end

  def calendar_weekday_labels
    I18n.t('calendar.weekday_initials')
  end

  def calendar_day_number(cell)
    Date.parse(cell[:date].to_s).day
  end

  # Returns the space-joined CSS class string for a calendar cell.
  # Heat bucket is precomputed by Timeline::MonthSummary as a month-relative
  # grade (1..5 = quintiles of the busiest day in the visible month;
  # 0 = no activity at all).
  def calendar_cell_classes(cell)
    bucket = cell[:heat_bucket].nil? ? heat_bucket(cell[:tracked_seconds]) : cell[:heat_bucket].to_i
    classes = ['cal-cell', "heat-#{bucket}"]
    classes << 'has-suggestions' if cell[:suggested_count].to_i.positive?
    classes << 'out-of-month' unless cell[:in_month]
    classes << 'disabled' if cell[:disabled]
    classes << (bucket >= 3 ? 'cal-cell--light-text' : 'cal-cell--dark-text')
    classes.join(' ')
  end
end
