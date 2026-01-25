# frozen_string_literal: true

# Service to split time ranges into processable chunks for parallel track generation
# Handles buffer zones to ensure tracks spanning multiple chunks are properly processed
class Tracks::TimeChunker
  attr_reader :user, :start_at, :end_at, :chunk_size, :buffer_size

  def initialize(user, start_at: nil, end_at: nil, chunk_size: 1.day, buffer_size: 6.hours)
    @user = user
    @start_at = start_at
    @end_at = end_at
    @chunk_size = chunk_size
    @buffer_size = buffer_size
  end

  def call
    time_range = determine_time_range
    return [] if time_range.nil?

    start_time, end_time = time_range
    return [] if start_time >= end_time

    chunks = []
    current_time = start_time

    while current_time < end_time
      chunk_end = [current_time + chunk_size, end_time].min

      chunk = create_chunk(current_time, chunk_end, start_time, end_time)
      chunks << chunk if chunk_has_points?(chunk)

      current_time = chunk_end
    end

    chunks
  end

  private

  def determine_time_range
    timezone = user.timezone
    current_time = Time.current.in_time_zone(timezone)

    case
    when start_at && end_at
      [start_at.to_time.in_time_zone(timezone), end_at.to_time.in_time_zone(timezone)]
    when start_at
      [start_at.to_time.in_time_zone(timezone), current_time]
    when end_at
      first_point_time = user.points.minimum(:timestamp)
      return nil unless first_point_time

      [Time.at(first_point_time).in_time_zone(timezone), end_at.to_time.in_time_zone(timezone)]
    else
      # Get full range from user's points
      first_point_time = user.points.minimum(:timestamp)
      last_point_time = user.points.maximum(:timestamp)

      return nil unless first_point_time && last_point_time

      [Time.at(first_point_time).in_time_zone(timezone), Time.at(last_point_time).in_time_zone(timezone)]
    end
  end

  def create_chunk(chunk_start, chunk_end, global_start, global_end)
    # Calculate buffer zones, but don't exceed global boundaries
    buffer_start = [chunk_start - buffer_size, global_start].max
    buffer_end = [chunk_end + buffer_size, global_end].min

    {
      chunk_id: SecureRandom.uuid,
      start_timestamp: chunk_start.to_i,
      end_timestamp: chunk_end.to_i,
      buffer_start_timestamp: buffer_start.to_i,
      buffer_end_timestamp: buffer_end.to_i,
      start_time: chunk_start,
      end_time: chunk_end,
      buffer_start_time: buffer_start,
      buffer_end_time: buffer_end
    }
  end

  def chunk_has_points?(chunk)
    # Check if there are any points in the buffer range to avoid empty chunks
    user.points
        .where(timestamp: chunk[:buffer_start_timestamp]..chunk[:buffer_end_timestamp])
        .exists?
  end
end
