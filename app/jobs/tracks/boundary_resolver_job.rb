# frozen_string_literal: true

# Resolves cross-chunk track boundaries and finalizes parallel track generation
# Runs after all chunk processors complete to handle tracks spanning multiple chunks
class Tracks::BoundaryResolverJob < ApplicationJob
  queue_as :tracks

  retry_on Tracks::PerUserLock::AcquisitionTimeout, wait: :polynomially_longer, attempts: 5 do |job, error|
    user_id, session_id = job.arguments
    Rails.logger.error(
      'Tracks::BoundaryResolverJob lock contention retries exhausted ' \
      "user_id=#{user_id}: #{error.message}"
    )
    Tracks::SessionManager.new(user_id, session_id).mark_failed(error.message) if session_id
  end

  MAX_RETRIES = 5

  def perform(user_id, session_id, retry_count = 0, seen_completed_chunks = -1, poll_count = 0)
    @user = find_user_or_skip(user_id) || return

    @session_manager = Tracks::SessionManager.new(user_id, session_id)
    @retry_count = retry_count
    @seen_completed_chunks = seen_completed_chunks
    @poll_count = poll_count

    return unless session_exists_and_ready?

    boundary_tracks_resolved = resolve_boundary_tracks
    finalize_session(boundary_tracks_resolved)
  rescue Tracks::PerUserLock::AcquisitionTimeout
    raise
  rescue StandardError => e
    ExceptionReporter.call(e, "Failed to resolve boundaries for user #{user_id}")

    mark_session_failed(e.message)
  end

  private

  attr_reader :user, :session_manager, :retry_count, :seen_completed_chunks, :poll_count

  def session_exists_and_ready?
    return false unless session_manager.session_exists?

    unless session_manager.all_chunks_completed?
      reschedule_boundary_resolution

      return false
    end

    true
  end

  def resolve_boundary_tracks
    Tracks::PerUserLock.with_user_lock(user.id) do
      Tracks::BoundaryDetector.new(user).resolve_cross_chunk_tracks
    end
  end

  def finalize_session(_boundary_tracks_resolved)
    session_manager.mark_completed
  end

  # Chunks that are still completing mean the fan-out is working, just slowly —
  # on a low-priority queue that can take far longer than the retry budget. Only
  # a session that made no progress since the last look burns an attempt.
  def reschedule_boundary_resolution
    completed_chunks = session_manager.get_session_data['completed_chunks'].to_i
    stalled = completed_chunks <= seen_completed_chunks
    attempts = stalled ? retry_count + 1 : 0

    if attempts >= MAX_RETRIES
      mark_session_failed("Max retries (#{MAX_RETRIES}) exceeded waiting for chunks to complete")
      return
    end

    # Backoff climbs with every look and never resets, so a fan-out that takes
    # hours is polled every 5 minutes rather than every 30 seconds. Only the
    # give-up budget resets when chunks are still landing.
    delay = [30.seconds * (2**poll_count), 5.minutes].min

    # queue_name, not the class default: a caller that routed this generation
    # onto another queue must keep it there across reschedules.
    self.class.set(wait: delay, queue: queue_name)
        .perform_later(user.id, session_manager.session_id, attempts, completed_chunks, poll_count + 1)
  end

  def mark_session_failed(error_message)
    session_manager.mark_failed(error_message)
  end
end
