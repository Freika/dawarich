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
