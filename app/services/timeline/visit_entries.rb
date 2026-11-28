# frozen_string_literal: true

module Timeline
  module VisitEntries
    def build_visit_entry(visit, date: nil)
      entry = {
        type: 'visit',
        visit_id: visit.id,
        name: visit.display_name,
        editable_name: visit.name,
        status: visit.status,
        confidence_band: visit.confidence_band,
        place_id: visit.place_id,
        center: point_center_for(visit),
        point_count: point_count_for(visit),
        tags: build_tags(visit.place),
        started_at: visit.started_at.iso8601,
        ended_at: visit.ended_at.iso8601,
        duration: visit.duration,
        place: visit.place ? build_place(visit.place) : nil,
        area: visit.area ? build_area(visit.area) : nil,
        local_timezone: local_timezone_for(visit)
      }

      entry[:suggested_places] = build_suggested_places(visit) if visit.suggested?
      entry.merge!(visit_day_part(visit, date)) if date

      entry
    end

    private

    def local_timezone_for(visit)
      return @local_timezones[[:visit, visit.id]] if @local_timezones

      Timezones::Lookup.call(visit: visit_location(visit))[:visit]
    end

    # The location the entry itself shows, so a visit a privacy zone hides
    # does not give its zone away either.
    def visit_location(visit)
      location = if visit.place then [visit.place.lon, visit.place.lat]
                 elsif visit.area then [visit.area.longitude.to_f, visit.area.latitude.to_f]
                 else point_center_for(visit)&.values_at(:lng, :lat)
                 end
      location unless location.nil? || @privacy_zone_masker&.in_zone?(*location)
    end

    def point_count_for(visit)
      assoc = visit.association(:points)
      return assoc.target.length if assoc.loaded?
      return @visit_point_counts.fetch(visit.id, 0) if @visit_point_counts

      visit.points.count
    end

    def visit_day_part(visit, date)
      start_day = visit.started_at.in_time_zone(timezone).to_date
      return { continuation_of_date: nil, day_duration: nil } if date == start_day

      share = TrackDayShares.shares_between(visit.started_at, visit.ended_at, timezone).fetch(date, 0.0)
      {
        continuation_of_date: start_day.to_s,
        day_duration: (visit.duration * share).round,
        day_started_at: date.in_time_zone(timezone).beginning_of_day.iso8601
      }
    end

    def build_area(area)
      {
        id: area.id,
        name: area.name,
        **visible_coordinates(area.latitude.to_f, area.longitude.to_f),
        radius: area.radius
      }
    end

    def build_tags(place)
      return [] unless place

      place.tags.map { |t| { id: t.id, name: t.name, icon: t.icon, color: t.color } }
    end

    def build_suggested_places(visit)
      seen = {}

      if visit.place.present?
        key = visit.place.name.to_s.strip.downcase
        unless key.empty?
          seen[key] = { id: visit.place.id, name: visit.place.name,
                        **visible_coordinates(visit.place.lat, visit.place.lon) }
        end
      end

      visit.suggested_places.each do |p|
        key = p.name.to_s.strip.downcase
        next if key.empty?

        seen[key] ||= { id: p.id, name: p.name, **visible_coordinates(p.lat, p.lon) }
      end

      seen.values
    end

    def build_place(place)
      {
        name: place.name,
        **visible_coordinates(place.lat, place.lon),
        city: place.city,
        country: place.country,
        visit_radius: place.visit_radius
      }
    end

    def visible_coordinates(lat, lng)
      return { lat: nil, lng: nil } if @privacy_zone_masker.in_zone?(lng, lat)

      { lat:, lng: }
    end

    def needs_point_center?(visit)
      visit.place.nil? && visit.area.nil?
    end

    def point_center_for(visit)
      return unless needs_point_center?(visit)
      return @visit_point_centers[visit.id] if @visit_point_centers

      Visits::PointCenters.new(user, visit_ids: [visit.id], privacy_zone_masker: @privacy_zone_masker).call[visit.id]
    end
  end
end
