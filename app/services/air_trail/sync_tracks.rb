# frozen_string_literal: true

module AirTrail
  class SyncTracks
    MAX_POINTS = 500

    def initialize(user, client)
      @user = user
      @client = client
    end

    def call
      summaries = @client.track_summaries

      @user.flights.where(external_id: summaries.keys).find_each do |flight|
        updated_at = parse_time(field(summaries[flight.external_id], 'updatedAt'))
        next if updated_at.nil? || updated_at == flight.track_updated_at

        coordinates = simplify(field(@client.track(flight.external_id), 'coordinates'))
        next if coordinates.nil?

        flight.update!(track_coordinates: coordinates, track_updated_at: updated_at)
      end
    rescue AirTrail::Client::Error => e
      Rails.logger.info("AirTrail track sync skipped for user #{@user.id}: #{e.message}")
    end

    private

    def field(hash, key)
      hash[key] if hash.is_a?(Hash)
    end

    def parse_time(value)
      value.is_a?(String) ? Time.zone.parse(value) : nil
    rescue ArgumentError
      nil
    end

    def simplify(coordinates)
      points = Array(coordinates).filter_map do |point|
        lon, lat = point if point.is_a?(Array)
        [lon, lat] if lon.is_a?(Numeric) && lat.is_a?(Numeric) && lon.abs <= 180 && lat.abs <= 90
      end
      return if points.size < 2
      return points if points.size <= MAX_POINTS

      step = (points.size - 1).fdiv(MAX_POINTS - 1)
      Array.new(MAX_POINTS) { |i| points[(i * step).round] }
    end
  end
end
