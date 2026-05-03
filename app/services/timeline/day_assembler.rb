# frozen_string_literal: true

module Timeline
  class DayAssembler
    # Hard cap on the requested window. The UI consumes day-by-day; ranges
    # this large would otherwise materialize thousands of LINESTRINGs in
    # memory just to compute bounds.
    MAX_RANGE = 31.days

    def initialize(user, start_at:, end_at:, distance_unit: 'km')
      @user = user
      @start_at = start_at.present? ? Time.zone.parse(start_at) : nil
      @end_at = end_at.present? ? Time.zone.parse(end_at) : nil
      @distance_unit = distance_unit
    end

    def call
      return [] if start_at.nil? || end_at.nil?
      return [] if (end_at - start_at) > MAX_RANGE

      visits = fetch_visits
      tracks = fetch_tracks

      return [] if visits.empty? && tracks.empty?

      days = group_by_day(visits, tracks)
      build_days(days)
    end

    # Public entry-point for building a single visit's hash payload — used by
    # VisitsController#update so the turbo_stream response can re-render the
    # row with fresh status / name / place / suggested_places data.
    # (Helpers it calls remain private; same-class access is allowed.)
    def build_visit_entry(visit)
      entry = {
        type: 'visit',
        visit_id: visit.id,
        name: visit.name,
        editable_name: visit.name,
        status: visit.status,
        place_id: visit.place_id,
        point_count: point_count_for(visit),
        tags: build_tags(visit.place),
        started_at: visit.started_at.iso8601,
        ended_at: visit.ended_at.iso8601,
        duration: visit.duration,
        place: visit.place ? build_place(visit.place) : nil,
        area: visit.area ? build_area(visit.area) : nil
      }

      entry[:suggested_places] = build_suggested_places(visit) if visit.suggested?

      entry
    end

    private

    attr_reader :user, :start_at, :end_at, :distance_unit

    def fetch_visits
      user.scoped_visits
          .includes(:area, suggested_places: :tags, place: :tags)
          .where(started_at: start_at..end_at)
          .order(started_at: :asc)
    end

    def point_count_for(visit)
      assoc = visit.association(:points)
      assoc.loaded? ? assoc.target.length : visit.points.count
    end

    def fetch_tracks
      user.scoped_tracks
          .where('start_at <= ? AND end_at >= ?', end_at, start_at)
          .order(start_at: :asc)
    end

    def group_by_day(visits, tracks)
      tz = user.safe_settings.timezone
      Time.use_zone(tz) do
        grouped = {}
        window = start_at.in_time_zone.to_date..end_at.in_time_zone.to_date

        visits.each do |visit|
          day_key = visit.started_at.in_time_zone.to_date
          next unless window.cover?(day_key)

          grouped[day_key] ||= empty_day_bucket
          grouped[day_key][:visits] << visit
        end

        tracks.each do |track|
          start_day = track.start_at.in_time_zone.to_date
          TrackDayShares.shares_for(track, tz).each do |day_key, fraction|
            next unless window.cover?(day_key)

            grouped[day_key] ||= empty_day_bucket
            grouped[day_key][:tracks] << track
            grouped[day_key][:track_shares][track.id] = fraction
            grouped[day_key][:originating_tracks] << track if day_key == start_day
          end
        end

        grouped.sort_by(&:first)
      end
    end

    # Continuation-day buckets share polyline geometry with their start day.
    # Auto-fit bounds use only `originating_tracks` so the camera frames "what
    # happened today" instead of zooming out to a city visited the prior
    # evening; the route layer still renders the full polyline independently.
    def empty_day_bucket
      { visits: [], tracks: [], originating_tracks: [], track_shares: {} }
    end

    def build_days(days)
      days.map { |date, data| build_day(date, data) }
    end

    def build_day(date, data)
      entries = interleave(date, data[:visits], data[:tracks], data[:track_shares])
      {
        date: date.to_s,
        summary: build_summary(data[:visits], data[:tracks], data[:track_shares]),
        bounds: build_bounds(data[:visits], data[:originating_tracks]),
        entries: entries
      }
    end

    # Sort key clamps continuation-day journeys to the day's 00:00 anchor so
    # they appear at the top of the day rather than ahead of all visits at
    # the previous evening's wall-clock. Visits never cross midnight in the
    # bucket (group_by_day keys them on their own start), so their sort key
    # is unchanged.
    def interleave(date, visits, tracks, track_shares)
      day_start_iso = date.in_time_zone(user.safe_settings.timezone).beginning_of_day.iso8601
      visit_entries = visits.map { |v| build_visit_entry(v) }
      track_entries = tracks.map { |t| build_journey_entry(t, date: date, day_share: track_shares.fetch(t.id, 1.0)) }

      (visit_entries + track_entries).sort_by do |entry|
        sort_key = entry[:started_at]
        sort_key = day_start_iso if sort_key < day_start_iso
        [sort_key, entry[:started_at]]
      end
    end

    # NOTE: visit.duration is stored in MINUTES. See the public #build_visit_entry
    # above for the entry payload shape.

    def build_area(area)
      {
        id: area.id,
        name: area.name,
        lat: area.latitude.to_f,
        lng: area.longitude.to_f,
        radius: area.radius
      }
    end

    def build_tags(place)
      return [] unless place

      place.tags.map { |t| { id: t.id, name: t.name, icon: t.icon, color: t.color } }
    end

    # Geocoder suggestions often include near-identical rows (same name,
    # slightly different ids). We dedupe by normalized name so the picker
    # UI can stay compact — if a user actually needs the tail, the view
    # reveals it behind a disclosure.
    def build_suggested_places(visit)
      seen = {}

      if visit.place.present?
        key = visit.place.name.to_s.strip.downcase
        unless key.empty?
          seen[key] = { id: visit.place.id, name: visit.place.name, lat: visit.place.lat, lng: visit.place.lon }
        end
      end

      visit.suggested_places.each do |p|
        key = p.name.to_s.strip.downcase
        next if key.empty?

        seen[key] ||= { id: p.id, name: p.name, lat: p.lat, lng: p.lon }
      end

      seen.values
    end

    def build_journey_entry(track, date: nil, day_share: 1.0)
      tz = user.safe_settings.timezone
      start_day = track.start_at.in_time_zone(tz).to_date
      continuation = date.present? && date != start_day

      {
        type: 'journey',
        track_id: track.id,
        started_at: track.start_at.iso8601,
        ended_at: track.end_at.iso8601,
        duration: track.duration,
        distance: convert_distance(track.distance),
        distance_unit: distance_unit,
        dominant_mode: track.dominant_mode,
        avg_speed: convert_speed(track.avg_speed.to_f),
        speed_unit: speed_unit_label,
        elevation_gain: track.elevation_gain,
        elevation_loss: track.elevation_loss,
        continuation_of_date: continuation ? start_day.to_s : nil,
        day_distance: continuation ? convert_distance(track.distance.to_f * day_share) : nil,
        day_duration: continuation ? (track.duration.to_f * day_share).round : nil
      }
    end

    def build_place(place)
      {
        name: place.name,
        lat: place.lat,
        lng: place.lon,
        city: place.city,
        country: place.country
      }
    end

    def build_summary(visits, tracks, track_shares)
      total_distance_m = tracks.sum { |t| t.distance.to_f * track_shares.fetch(t.id, 1.0) }
      moving_seconds = tracks.sum { |t| t.duration.to_f * track_shares.fetch(t.id, 1.0) }
      # NOTE: visit.duration is stored in MINUTES (see Visits::Creator / Visits::Create).
      stationary_minutes = visits.sum(&:duration)
      status_counts = visits.group_by(&:status).transform_values(&:size)

      {
        total_distance: convert_distance(total_distance_m),
        distance_unit: distance_unit,
        places_visited: visits.flat_map(&:place_id).compact.uniq.length,
        time_moving_minutes: (moving_seconds / 60.0).round,
        time_stationary_minutes: stationary_minutes,
        suggested_count: status_counts.fetch('suggested', 0),
        confirmed_count: status_counts.fetch('confirmed', 0),
        declined_count: status_counts.fetch('declined', 0)
      }
    end

    def build_bounds(visits, tracks)
      lats = []
      lngs = []

      visits.each do |visit|
        next unless visit.place

        lats << visit.place.lat
        lngs << visit.place.lon
      end

      track_extent = tracks_extent(tracks)
      if track_extent
        lats << track_extent[:min_lat] << track_extent[:max_lat]
        lngs << track_extent[:min_lng] << track_extent[:max_lng]
      end

      return nil if lats.empty? || lngs.empty?

      {
        sw_lat: lats.min,
        sw_lng: lngs.min,
        ne_lat: lats.max,
        ne_lng: lngs.max
      }
    end

    # Single PostGIS aggregate over all tracks in the day instead of
    # materializing each LINESTRING into Ruby. Returns nil if no tracks
    # have a path.
    def tracks_extent(tracks)
      track_ids = tracks.map(&:id)
      return nil if track_ids.empty?

      query = <<~SQL.squish
        SELECT
          ST_XMin(extent) AS min_lng,
          ST_YMin(extent) AS min_lat,
          ST_XMax(extent) AS max_lng,
          ST_YMax(extent) AS max_lat
        FROM (
          SELECT ST_Extent(original_path::geometry) AS extent
          FROM tracks
          WHERE id IN (?) AND original_path IS NOT NULL
        ) sub
      SQL
      sql = ActiveRecord::Base.sanitize_sql_array([query, track_ids])

      row = ActiveRecord::Base.connection.exec_query(sql).first
      return nil unless row && row['min_lng']

      {
        min_lng: row['min_lng'].to_f,
        min_lat: row['min_lat'].to_f,
        max_lng: row['max_lng'].to_f,
        max_lat: row['max_lat'].to_f
      }
    end

    def convert_distance(meters)
      Stat.convert_distance(meters, distance_unit).round(1)
    end

    def convert_speed(kmh)
      return 0.0 if kmh.zero?

      case distance_unit
      when 'mi' then (kmh * 0.621371).round(1)
      else kmh.round(1)
      end
    end

    def speed_unit_label
      case distance_unit
      when 'mi' then 'mph'
      else 'km/h'
      end
    end
  end
end
