# frozen_string_literal: true

module SharedLinks
  class TripDays
    COLORS = %w[
      #6366F1 #F43F5E #10B981 #F59E0B #0EA5E9 #A855F7
      #F97316 #14B8A6 #EC4899 #84CC16 #06B6D4 #D946EF
    ].freeze

    def initialize(trip, timezone:, unit:)
      @trip = trip
      @timezone = timezone.presence || 'UTC'
      @unit = unit.presence || 'km'
    end

    def call
      stats = day_stats
      date_range.each_with_index.map do |date, index|
        row = stats[date]
        {
          date: date,
          weekday: I18n.l(date, format: '%A'),
          label: I18n.l(date, format: :short_month_day),
          color: COLORS[index % COLORS.size],
          has_data: row.present?,
          first_time: row && row[:first_time],
          last_time: row && row[:last_time],
          distance_label: row && distance_label(row[:distance_m]),
          bounds: row && row[:bounds],
          first_coordinates: row && row[:first_coordinates],
          last_coordinates: row && row[:last_coordinates]
        }
      end
    end

    private

    def date_range
      start_date = @trip.started_at.in_time_zone(@timezone).to_date
      end_date   = @trip.ended_at.in_time_zone(@timezone).to_date
      (start_date..end_date).to_a
    end

    def day_stats
      @trip.day_stats(@timezone, points_scope: points_outside_privacy_zones)
    end

    def points_outside_privacy_zones
      points = @trip.plan_scoped_route_points
      zones = privacy_zones
      return points if zones.empty?

      condition = zones.map { 'ST_DWithin(points.lonlat, ST_SetSRID(ST_MakePoint(?, ?), 4326)::geography, ?)' }
                       .join(' OR ')
      points.where.not(condition, *zones.flat_map { |z| [z[:lon], z[:lat], z[:radius]] })
    end

    def privacy_zones
      @privacy_zones ||= @trip.user.tags.privacy_zones.includes(:places).flat_map do |tag|
        tag.places.map do |place|
          { lon: place.longitude.to_f, lat: place.latitude.to_f, radius: tag.privacy_radius_meters }
        end
      end
    end

    def distance_label(distance_m)
      value = Trip.convert_distance(distance_m, @unit)
      return "< 1 #{@unit}" if value < 1

      "#{ActiveSupport::NumberHelper.number_to_rounded(value, precision: 1)} #{@unit}"
    end
  end
end
