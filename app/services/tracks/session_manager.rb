# frozen_string_literal: true

# Rails cache-based session management for parallel track generation
# Handles job coordination, progress tracking, and cleanup
class Tracks::SessionManager
  CACHE_KEY_PREFIX = 'track_generation'
  DEFAULT_TTL = 24.hours

  attr_reader :user_id, :session_id

  def initialize(user_id, session_id = nil)
    @user_id = user_id
    @session_id = session_id || SecureRandom.uuid
  end

  # Create a new session
  def create_session(metadata = {})
    session_data = {
      'status' => 'pending',
      'total_chunks' => 0,
      'completed_chunks' => 0,
      'tracks_created' => 0,
      'started_at' => Time.current.iso8601,
      'completed_at' => nil,
      'error_message' => nil,
      'metadata' => metadata.deep_stringify_keys
    }

    Rails.cache.write(cache_key, session_data, expires_in: DEFAULT_TTL)
    # Initialize counters atomically using Redis SET
    Rails.cache.redis.with do |redis|
      redis.set(counter_key('completed_chunks'), 0, ex: DEFAULT_TTL.to_i)
      redis.set(counter_key('tracks_created'), 0, ex: DEFAULT_TTL.to_i)
    end

    self
  end

  # Update session data
  def update_session(updates)
    current_data = get_session_data
    return false unless current_data

    updated_data = current_data.merge(updates.deep_stringify_keys)
    Rails.cache.write(cache_key, updated_data, expires_in: DEFAULT_TTL)
    true
  end

  # Get session data
  def get_session_data
    data = Rails.cache.read(cache_key)
    return nil unless data

    # Include current counter values
    data['completed_chunks'] = counter_value('completed_chunks')
    data['tracks_created'] = counter_value('tracks_created')
    data
  end

  # Check if session exists
  def session_exists?
    Rails.cache.exist?(cache_key)
  end

  # Mark session as started
  def mark_started(total_chunks)
    update_session(
      status: 'processing',
      total_chunks: total_chunks,
      started_at: Time.current.iso8601
    )
  end

  # Increment completed chunks
  def increment_completed_chunks
    return false unless session_exists?

    atomic_increment(counter_key('completed_chunks'), 1)
    true
  end

  # Increment tracks created
  def increment_tracks_created(count = 1)
    return false unless session_exists?

    atomic_increment(counter_key('tracks_created'), count)
    true
  end

  # Mark session as completed
  def mark_completed
    update_session(
      status: 'completed',
      completed_at: Time.current.iso8601
    )
  end

  # Mark session as failed
  def mark_failed(error_message)
    update_session(
      status: 'failed',
      error_message: error_message,
      completed_at: Time.current.iso8601
    )
  end

  # Check if all chunks are completed
  def all_chunks_completed?
    session_data = get_session_data
    return false unless session_data

    completed_chunks = counter_value('completed_chunks')
    completed_chunks >= session_data['total_chunks']
  end

  # Get progress percentage
  def progress_percentage
    session_data = get_session_data
    return 0 unless session_data

    total = session_data['total_chunks']
    return 100 if total.zero?

    completed = counter_value('completed_chunks')
    (completed.to_f / total * 100).round(2)
  end

  # Delete session
  def cleanup_session
    Rails.cache.delete(cache_key)
    Rails.cache.redis.with do |redis|
      redis.del(counter_key('completed_chunks'), counter_key('tracks_created'))
    end
  end

  # Class methods for session management
  class << self
    # Create session for user
    def create_for_user(user_id, metadata = {})
      new(user_id).create_session(metadata)
    end

    # Find session by user and session ID
    def find_session(user_id, session_id)
      manager = new(user_id, session_id)
      manager.session_exists? ? manager : nil
    end

    # Cleanup expired sessions (automatic with Rails cache TTL)
    def cleanup_expired_sessions
      # With Rails cache, expired keys are automatically cleaned up
      # This method exists for compatibility but is essentially a no-op
      true
    end
  end

  private

  def cache_key
    "#{CACHE_KEY_PREFIX}:user:#{user_id}:session:#{session_id}"
  end

  def counter_key(field)
    "#{cache_key}:#{field}"
  end

  def counter_value(field)
    Rails.cache.redis.with do |redis|
      (redis.get(counter_key(field)) || 0).to_i
    end
  end

  def atomic_increment(key, amount)
    Rails.cache.redis.with do |redis|
      redis.incrby(key, amount)
    end
  end
end
