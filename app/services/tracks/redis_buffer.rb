# frozen_string_literal: true

class Tracks::RedisBuffer
  BUFFER_PREFIX = 'track_buffer'
  BUFFER_EXPIRY = 7.days

  attr_reader :user_id, :day

  def initialize(user_id, day)
    @user_id = user_id
    @day = day.is_a?(Date) ? day : Date.parse(day.to_s)
  end

  # Store buffered points for an incomplete track segment
  # @param points [Array<Point>] array of Point objects to buffer
  def store(points)
    return if points.empty?

    points_data = serialize_points(points)
    redis_key = buffer_key

    Rails.cache.write(redis_key, points_data, expires_in: BUFFER_EXPIRY)
    Rails.logger.debug "Stored #{points.size} points in buffer for user #{user_id}, day #{day}"
  end

  # Retrieve buffered points for the user/day combination
  # @return [Array<Hash>] array of point hashes or empty array if no buffer exists
  def retrieve
    redis_key = buffer_key
    cached_data = Rails.cache.read(redis_key)

    return [] unless cached_data

    deserialize_points(cached_data)
  rescue StandardError => e
    Rails.logger.error "Failed to retrieve buffered points for user #{user_id}, day #{day}: #{e.message}"
    []
  end

  # Clear the buffer for the user/day combination
  def clear
    redis_key = buffer_key
    Rails.cache.delete(redis_key)
    Rails.logger.debug "Cleared buffer for user #{user_id}, day #{day}"
  end

  # Check if a buffer exists for the user/day combination
  # @return [Boolean] true if buffer exists, false otherwise
  def exists?
    Rails.cache.exist?(buffer_key)
  end

  private

  def buffer_key
    "#{BUFFER_PREFIX}:#{user_id}:#{day.strftime('%Y-%m-%d')}"
  end

  def serialize_points(points)
    points.map do |point|
      {
        id: point.id,
        lonlat: point.lonlat.to_s,
        timestamp: point.timestamp,
        lat: point.lat,
        lon: point.lon,
        altitude: point.altitude,
        velocity: point.velocity,
        battery: point.battery,
        user_id: point.user_id
      }
    end
  end

  def deserialize_points(points_data)
    points_data || []
  end
end
