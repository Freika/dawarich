# frozen_string_literal: true

module Timeline
  class DayAssembler
    def initialize(user, start_at:, end_at:)
      @user = user
      @start_at = Time.zone.parse(start_at)
      @end_at = Time.zone.parse(end_at)
    end

    def call
      visits = fetch_visits
      tracks = fetch_tracks

      return [] if visits.empty? && tracks.empty?

      days = group_by_day(visits, tracks)
      build_days(days)
    end

    private

    attr_reader :user, :start_at, :end_at

    def fetch_visits
      user.visits
          .includes(:place, :area)
          .where(started_at: start_at..end_at)
          .order(started_at: :asc)
    end

    def fetch_tracks
      user.tracks
          .where(start_at: start_at..end_at)
          .order(start_at: :asc)
    end

    def group_by_day(visits, tracks)
      grouped = {}

      visits.each do |visit|
        day_key = visit.started_at.to_date
        grouped[day_key] ||= { visits: [], tracks: [] }
        grouped[day_key][:visits] << visit
      end

      tracks.each do |track|
        day_key = track.start_at.to_date
        grouped[day_key] ||= { visits: [], tracks: [] }
        grouped[day_key][:tracks] << track
      end

      grouped.sort_by(&:first)
    end

    def build_days(days)
      days.map { |date, data| build_day(date, data[:visits], data[:tracks]) }
    end

    def build_day(date, visits, tracks)
      entries = interleave(visits, tracks)
      {
        date: date.to_s,
        summary: build_summary(visits, tracks),
        bounds: build_bounds(visits, tracks),
        entries: entries
      }
    end

    def interleave(visits, tracks)
      visit_entries = visits.map { |v| build_visit_entry(v) }
      track_entries = tracks.map { |t| build_journey_entry(t) }

      (visit_entries + track_entries).sort_by { |e| e[:started_at] }
    end

    def build_visit_entry(visit)
      {
        type: 'visit',
        visit_id: visit.id,
        name: visit.name,
        started_at: visit.started_at.iso8601,
        ended_at: visit.ended_at.iso8601,
        duration: visit.duration,
        place: visit.place ? build_place(visit.place) : nil
      }
    end

    def build_journey_entry(track)
      {
        type: 'journey',
        track_id: track.id,
        started_at: track.start_at.iso8601,
        ended_at: track.end_at.iso8601,
        duration: track.duration,
        distance_km: (track.distance / 1000.0).round(1),
        dominant_mode: track.dominant_mode,
        avg_speed_kmh: track.avg_speed.to_f.round(1),
        elevation_gain: track.elevation_gain,
        elevation_loss: track.elevation_loss
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

    def build_summary(visits, tracks)
      total_distance_m = tracks.sum(&:distance)
      moving_seconds = tracks.sum(&:duration)
      stationary_seconds = visits.sum(&:duration)

      {
        total_distance_km: (total_distance_m / 1000.0).round(1),
        places_visited: visits.flat_map(&:place_id).compact.uniq.length,
        time_moving_minutes: (moving_seconds / 60.0).round,
        time_stationary_minutes: (stationary_seconds / 60.0).round
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

      tracks.each do |track|
        coords = extract_track_coordinates(track)
        coords.each do |lng, lat|
          lats << lat
          lngs << lng
        end
      end

      return nil if lats.empty? || lngs.empty?

      {
        sw_lat: lats.min,
        sw_lng: lngs.min,
        ne_lat: lats.max,
        ne_lng: lngs.max
      }
    end

    def extract_track_coordinates(track)
      return [] if track.original_path.blank?

      if track.original_path.respond_to?(:coordinates)
        track.original_path.coordinates
      else
        parse_linestring(track.original_path.to_s)
      end
    end

    def parse_linestring(wkt)
      match = wkt.match(/LINESTRING\s*\((.+)\)/i)
      return [] unless match

      match[1].split(',').map do |pair|
        pair.strip.split(/\s+/).map(&:to_f)
      end
    end
  end
end
