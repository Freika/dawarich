# frozen_string_literal: true

# Main orchestrator service for parallel track generation
# Coordinates time chunking, job scheduling, and session management
class Tracks::ParallelGenerator
  include Tracks::Segmentation
  include Tracks::TrackBuilder

  attr_reader :user, :start_at, :end_at, :mode, :chunk_size

  def initialize(user, start_at: nil, end_at: nil, mode: :bulk, chunk_size: 1.day)
    @user = user
    @start_at = start_at
    @end_at = end_at
    @mode = mode.to_sym
    @chunk_size = chunk_size
  end

  def call
    # Clean existing tracks if needed
    clean_existing_tracks if should_clean_tracks?

    # Generate time chunks
    time_chunks = generate_time_chunks
    return 0 if time_chunks.empty?

    # Create session for tracking progress
    session = create_generation_session(time_chunks.size)

    # Enqueue chunk processing jobs
    enqueue_chunk_jobs(session.session_id, time_chunks)

    # Enqueue boundary resolver job (with delay to let chunks complete)
    enqueue_boundary_resolver(session.session_id, time_chunks.size)

    Rails.logger.info "Started parallel track generation for user #{user.id} with #{time_chunks.size} chunks (session: #{session.session_id})"
    
    session
  end

  private

  def should_clean_tracks?
    case mode
    when :bulk, :daily then true
    else false
    end
  end

  def generate_time_chunks
    chunker = Tracks::TimeChunker.new(
      user,
      start_at: start_at,
      end_at: end_at,
      chunk_size: chunk_size
    )
    
    chunker.call
  end

  def create_generation_session(total_chunks)
    metadata = {
      mode: mode.to_s,
      chunk_size: humanize_duration(chunk_size),
      start_at: start_at&.iso8601,
      end_at: end_at&.iso8601,
      user_settings: {
        time_threshold_minutes: time_threshold_minutes,
        distance_threshold_meters: distance_threshold_meters
      }
    }

    session_manager = Tracks::SessionManager.create_for_user(user.id, metadata)
    session_manager.mark_started(total_chunks)
    session_manager
  end

  def enqueue_chunk_jobs(session_id, time_chunks)
    time_chunks.each do |chunk|
      Tracks::TimeChunkProcessorJob.perform_later(
        user.id,
        session_id,
        chunk
      )
    end
  end

  def enqueue_boundary_resolver(session_id, chunk_count)
    # Delay based on estimated processing time (30 seconds per chunk + buffer)
    estimated_delay = [chunk_count * 30.seconds, 5.minutes].max
    
    Tracks::BoundaryResolverJob.set(wait: estimated_delay).perform_later(
      user.id,
      session_id
    )
  end

  def clean_existing_tracks
    case mode
    when :bulk then clean_bulk_tracks
    when :daily then clean_daily_tracks
    else
      raise ArgumentError, "Unknown mode: #{mode}"
    end
  end

  def clean_bulk_tracks
    scope = user.tracks
    scope = scope.where(start_at: time_range) if time_range_defined?
    
    Rails.logger.info "Cleaning #{scope.count} existing tracks for bulk regeneration (user: #{user.id})"
    scope.destroy_all
  end

  def clean_daily_tracks
    day_range = daily_time_range
    range = Time.zone.at(day_range.begin)..Time.zone.at(day_range.end)

    scope = user.tracks.where(start_at: range)
    Rails.logger.info "Cleaning #{scope.count} existing tracks for daily regeneration (user: #{user.id})"
    scope.destroy_all
  end

  def time_range_defined?
    start_at.present? || end_at.present?
  end

  def time_range
    return nil unless time_range_defined?

    start_time = start_at&.to_i
    end_time = end_at&.to_i

    if start_time && end_time
      Time.zone.at(start_time)..Time.zone.at(end_time)
    elsif start_time
      Time.zone.at(start_time)..
    elsif end_time
      ..Time.zone.at(end_time)
    end
  end

  def daily_time_range
    day = start_at&.to_date || Date.current
    day.beginning_of_day.to_i..day.end_of_day.to_i
  end

  def distance_threshold_meters
    @distance_threshold_meters ||= user.safe_settings.meters_between_routes.to_i
  end

  def time_threshold_minutes
    @time_threshold_minutes ||= user.safe_settings.minutes_between_routes.to_i
  end

  def humanize_duration(duration)
    case duration
    when 1.day then '1 day'
    when 1.hour then '1 hour'
    when 6.hours then '6 hours'
    when 12.hours then '12 hours'
    when 2.days then '2 days'
    when 1.week then '1 week'
    else
      # Convert seconds to readable format
      seconds = duration.to_i
      if seconds >= 86400 # days
        days = seconds / 86400
        "#{days} day#{'s' if days != 1}"
      elsif seconds >= 3600 # hours
        hours = seconds / 3600
        "#{hours} hour#{'s' if hours != 1}"
      elsif seconds >= 60 # minutes
        minutes = seconds / 60
        "#{minutes} minute#{'s' if minutes != 1}"
      else
        "#{seconds} second#{'s' if seconds != 1}"
      end
    end
  end
end