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
          weekday: date.strftime('%A'),
          label: date.strftime('%b %-d'),
          color: COLORS[index % COLORS.size],
          has_data: row.present?,
          first_time: row && row[:first_time],
          last_time: row && row[:last_time],
          distance_label: row && distance_label(row[:distance_m])
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
      tz_quoted = ActiveRecord::Base.connection.quote(@timezone)
      day_expr  = "(to_timestamp(timestamp) AT TIME ZONE 'UTC' AT TIME ZONE #{tz_quoted})::date"

      points_outside_privacy_zones.reorder(nil).group(Arel.sql(day_expr)).pluck(
        Arel.sql(day_expr),
        Arel.sql('MIN(timestamp)'),
        Arel.sql('MAX(timestamp)'),
        Arel.sql('COALESCE(ST_Length(ST_MakeLine(lonlat::geometry ORDER BY timestamp)::geography), 0)')
      ).each_with_object({}) do |(day, first_ts, last_ts, distance_m), acc|
        date = day.is_a?(Date) ? day : Date.parse(day.to_s)
        acc[date] = {
          first_time: Time.at(first_ts).in_time_zone(@timezone),
          last_time:  Time.at(last_ts).in_time_zone(@timezone),
          distance_m: distance_m.to_f
        }
      end
    end

    def points_outside_privacy_zones
      zones = privacy_zones
      return @trip.points if zones.empty?

      condition = zones.map { 'ST_DWithin(lonlat, ST_SetSRID(ST_MakePoint(?, ?), 4326)::geography, ?)' }
                       .join(' OR ')
      @trip.points.where.not(condition, *zones.flat_map { |z| [z[:lon], z[:lat], z[:radius]] })
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
