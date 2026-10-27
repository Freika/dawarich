# frozen_string_literal: true

module Timeline
  class DayAssembler
    include VisitEntries
    include DayBounds

    # Hard cap on the requested window. The UI consumes day-by-day; ranges
    # this large would otherwise materialize thousands of LINESTRINGs in
    # memory just to compute bounds.
    MAX_RANGE = 31.days

    PHANTOM_STATIONARY_DISTANCE_M = 100

    # Modes that never count as movement in summaries or journey rows.
    NON_MOVING_MODES = %w[stationary unknown].freeze
    # Segments below this posterior don't get to claim a mode in the day
    # chips (matches the display gate in TrackSegments::DisplayLegs).
    CHIP_CONFIDENCE_MIN = TrackSegments::DisplayLegs::UNCERTAIN_BELOW
    # Modes that moved less than this (in the user's display unit) stay off
    # the day chips — a 200 m jog across a parking lot is not a story.
    CHIP_MIN_DISTANCE = 0.5

    def initialize(user, start_at:, end_at:, distance_unit: 'km', privacy_zone_masker: nil)
      @user = user
      @privacy_zone_masker = privacy_zone_masker
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

      @segment_stats = load_segment_stats(tracks)

      ids = visits.select { |visit| needs_point_center?(visit) }.map(&:id)
      @visit_point_centers = Visits::PointCenters.new(user, visit_ids: ids,
                                                          privacy_zone_masker: @privacy_zone_masker).call
      @visit_point_counts = Point.where(visit_id: visits.map(&:id)).group(:visit_id).count

      days = group_by_day(visits, tracks)
      build_days(days)
    end

    private

    attr_reader :user, :start_at, :end_at, :distance_unit

    def timezone
      @timezone ||= user.safe_settings.timezone
    end

    def fetch_visits
      user.scoped_visits
          .includes(:area, suggested_places: :tags, place: :tags)
          .overlapping(start_at, end_at)
          .order(started_at: :asc)
    end

    def fetch_tracks
      user.scoped_tracks
          .where('start_at <= ? AND end_at >= ?', end_at, start_at)
          .without_phantom_stationary(PHANTOM_STATIONARY_DISTANCE_M)
          .order(start_at: :asc)
    end

    # Two grouped sums over the whole window's segments: per-track moving
    # seconds (any non-stationary movement, however uncertain) and per-track
    # per-mode confident distances for the day chips.
    def load_segment_stats(tracks)
      ids = tracks.map(&:id)
      return { moving: {}, mode_distances: {} } if ids.empty?

      moving_scope = TrackSegment.where(track_id: ids)
                                 .where.not(transportation_mode: NON_MOVING_MODES)
      {
        moving: moving_scope.group(:track_id).sum(:duration),
        mode_distances: moving_scope
                        .where('corrected_at IS NOT NULL OR confidence_score IS NULL OR confidence_score >= ?',
                               CHIP_CONFIDENCE_MIN)
                        .group(:track_id, :transportation_mode).sum(:distance)
      }
    end

    def group_by_day(visits, tracks)
      Time.use_zone(timezone) do
        grouped = {}
        window = start_at.in_time_zone.to_date..end_at.in_time_zone.to_date

        visits.each do |visit|
          TrackDayShares.shares_between(visit.started_at, visit.ended_at, timezone).each do |day_key, fraction|
            next unless window.cover?(day_key)

            grouped[day_key] ||= empty_day_bucket
            grouped[day_key][:visits] << visit
            grouped[day_key][:visit_shares][visit.id] = fraction
          end
        end

        tracks.each do |track|
          start_day = track.start_at.in_time_zone.to_date
          TrackDayShares.shares_for(track, timezone).each do |day_key, fraction|
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

    def empty_day_bucket
      { visits: [], tracks: [], originating_tracks: [], track_shares: {}, visit_shares: {} }
    end

    def build_days(days)
      days.map { |date, data| build_day(date, data) }
    end

    def build_day(date, data)
      entries = interleave(date, data, data[:track_shares])
      {
        date: date.to_s,
        summary: build_summary(data[:visits], data[:tracks], data[:track_shares], data[:visit_shares]),
        bounds: build_bounds(data[:visits], data[:originating_tracks]),
        entries: entries
      }
    end

    def interleave(date, data, track_shares)
      day_local = date.in_time_zone(timezone)
      day_start = day_local.beginning_of_day
      day_end = day_local.end_of_day
      visit_entries = data[:visits].map { |v| build_visit_entry(v, date: date) }
      track_entries = data[:tracks].map do |t|
        build_journey_entry(t, date: date, day_share: track_shares.fetch(t.id, 1.0))
      end

      (visit_entries + track_entries).sort_by do |entry|
        started_at_time = Time.iso8601(entry[:started_at])
        anchor_time = if entry[:type] == 'journey' && entry[:continuation_of_date]
                        ended_at_time = Time.iso8601(entry[:ended_at])
                        [[ended_at_time, day_end].min, day_start].max
                      else
                        started_at_time
                      end
        [anchor_time, started_at_time]
      end
    end

    def build_journey_entry(track, date: nil, day_share: 1.0)
      start_day = track.start_at.in_time_zone(timezone).to_date
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
        day_duration: continuation ? (track.duration.to_f * day_share).round : nil,
        moving_duration: day_moving_duration(track, continuation, day_share)
      }
    end

    # Continuation rows describe one day's slice of the track, so moving time
    # has to be apportioned the same way distance and duration are.
    def day_moving_duration(track, continuation, day_share)
      moving = @segment_stats[:moving][track.id]
      return moving unless continuation && moving

      (moving.to_f * day_share).round
    end

    def build_summary(visits, tracks, track_shares, visit_shares)
      total_distance_m = tracks.sum { |t| t.distance.to_f * track_shares.fetch(t.id, 1.0) }
      # Asymmetry with fetch_tracks is intentional: stationary tracks with >=100m
      # still surface in the timeline as "🛑 stayed" rows, but their duration must
      # not contribute to "time_moving_minutes" — "stayed" is not "moving".
      moving_tracks = tracks.reject { |t| t.dominant_mode == 'stationary' }
      moving_seconds = moving_tracks.sum { |t| t.duration.to_f * track_shares.fetch(t.id, 1.0) }
      # NOTE: visit.duration is stored in MINUTES (see Visits::Creator / Visits::Create).
      stationary_minutes = visits.sum { |v| (v.duration * visit_shares.fetch(v.id, 1.0)).round }
      status_counts = visits.group_by(&:status).transform_values(&:size)

      {
        total_distance: convert_distance(total_distance_m),
        distance_unit: distance_unit,
        places_visited: visits.flat_map(&:place_id).compact.uniq.length,
        time_moving_minutes: (moving_seconds / 60.0).round,
        time_stationary_minutes: stationary_minutes,
        suggested_count: status_counts.fetch('suggested', 0),
        confirmed_count: status_counts.fetch('confirmed', 0),
        declined_count: status_counts.fetch('declined', 0),
        mode_distances: mode_distances_for(tracks, track_shares)
      }
    end

    def mode_distances_for(tracks, track_shares)
      day_track_ids = tracks.map(&:id).to_set
      totals = Hash.new(0.0)

      @segment_stats[:mode_distances].each do |(track_id, mode), meters|
        next unless day_track_ids.include?(track_id)

        totals[mode] += meters.to_f * track_shares.fetch(track_id, 1.0)
      end

      totals.transform_values { |meters| convert_distance(meters) }
            .reject { |_, value| value < CHIP_MIN_DISTANCE }
            .sort_by { |_, value| -value }
            .to_h
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
