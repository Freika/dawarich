# frozen_string_literal: true

module Tracks
  # Manages the status of transportation mode recalculation for a user.
  # Handles cache operations for tracking progress and state.
  class TransportationRecalculationStatus
    CACHE_KEY_PREFIX = 'transportation_mode_recalculation'
    CACHE_TTL = 24.hours
    COMPLETED_TTL = 5.minutes
    FAILED_TTL = 1.hour

    attr_reader :user_id

    def initialize(user_id)
      @user_id = user_id
    end

    def in_progress?
      current_status == 'processing'
    end

    def current_status
      data['status']
    end

    def data
      Rails.cache.read(cache_key) || { 'status' => 'idle' }
    end

    def start(total_tracks:)
      reset_counter
      Rails.cache.write(
        cache_key,
        {
          'status' => 'processing',
          'started_at' => Time.current.iso8601,
          'total_tracks' => total_tracks,
          'processed_tracks' => 0
        },
        expires_in: CACHE_TTL
      )
    end

    # Atomic-ish progress bump used by fan-out per-track jobs. The raw counter
    # is race-free under Rails.cache.increment; the merged status hash is
    # advisory display state.
    def increment_processed!
      # A retried per-track job can report after completion; rewriting the
      # hash would resurrect the short-lived 'completed' entry with CACHE_TTL.
      return data['processed_tracks'].to_i if current_status == 'completed'

      count = Rails.cache.increment(counter_key, 1, expires_in: CACHE_TTL) || 1
      total = data['total_tracks']
      update_progress(processed_tracks: count, total_tracks: total)
      complete if total && count >= total
      count
    end

    def reset_counter
      Rails.cache.write(counter_key, 0, raw: true, expires_in: CACHE_TTL)
    end

    def counter_key
      "#{cache_key}:processed_counter"
    end

    def update_progress(processed_tracks:, total_tracks:)
      current = Rails.cache.read(cache_key) || {}
      Rails.cache.write(
        cache_key,
        current.merge(
          'processed_tracks' => processed_tracks,
          'total_tracks' => total_tracks
        ),
        expires_in: CACHE_TTL
      )
    end

    def complete
      current = Rails.cache.read(cache_key) || {}
      Rails.cache.write(
        cache_key,
        current.merge(
          'status' => 'completed',
          'completed_at' => Time.current.iso8601
        ),
        expires_in: COMPLETED_TTL
      )
    end

    def fail(error_message)
      current = Rails.cache.read(cache_key) || {}
      Rails.cache.write(
        cache_key,
        current.merge(
          'status' => 'failed',
          'error_message' => error_message,
          'completed_at' => Time.current.iso8601
        ),
        expires_in: FAILED_TTL
      )
    end

    def cache_key
      "#{CACHE_KEY_PREFIX}:user:#{user_id}"
    end
  end
end
