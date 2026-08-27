# frozen_string_literal: true

class Points::PostIngestActions
  RECOVERABLE_ERRORS = [RedisClient::ConnectionError, Redis::BaseConnectionError, ConnectionPool::TimeoutError].freeze
  WARNING_INTERVAL = 1.minute

  def initialize(user_id:, timestamps:, points:, payload:, batch: nil)
    @user_id = user_id
    @timestamps = timestamps.compact
    @points = points
    @payload = payload
    @batch = batch
  end

  def call
    pending_batch = batch || create_pending_batch

    schedule(:anomaly_filter) do
      Points::AnomalyFilterJob.perform_later(user_id, timestamps.min, timestamps.max) if timestamps.any?
    end
    schedule(:realtime_tracks) { Tracks::RealtimeDebouncer.new(user_id).trigger }
    schedule(:track_backfill) { Tracks::BackfillScheduler.new(user_id, timestamps).call }
    schedule(:realtime_visits) { Visits::RealtimeDebouncer.new(user_id).trigger }
    pending_batch&.destroy!
    schedule(:live_broadcast) { Points::LiveBroadcaster.new(user_id, points, payload).call } unless batch
  rescue *RECOVERABLE_ERRORS => e
    warn_unavailable(e)
  end

  private

  attr_reader :user_id, :timestamps, :points, :payload, :batch, :action

  def create_pending_batch
    return if timestamps.empty?

    Points::PostIngestBatch.find_or_create_by!(
      user_id:,
      start_at: timestamps.min,
      end_at: timestamps.max
    )
  end

  def schedule(action)
    @action = action
    yield
  end

  def warn_unavailable(error)
    return unless self.class.log_warning?(action, error.class)

    Rails.logger.warn(
      "event=points.post_ingest_unavailable action=#{action} user_id=#{user_id} " \
      "error=#{error.class} message=#{error.message}"
    )
  end

  class << self
    def log_warning?(action, error_class)
      warning_lock.synchronize do
        now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        key = [action, error_class]
        last_warning = warning_times[key]
        warning_times[key] = now if last_warning.nil? || now - last_warning >= WARNING_INTERVAL
        last_warning.nil? || now - last_warning >= WARNING_INTERVAL
      end
    end

    private

    def warning_lock
      @warning_lock ||= Mutex.new
    end

    def warning_times
      @warning_times ||= {}
    end
  end
end
