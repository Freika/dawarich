# frozen_string_literal: true

# Resolves cross-chunk track boundaries and finalizes parallel track generation
# Runs after all chunk processors complete to handle tracks spanning multiple chunks
class Tracks::BoundaryResolverJob < ApplicationJob
  queue_as :tracks

  MAX_RETRIES = 5

  def perform(user_id, session_id, retry_count = 0)
    @user = User.find(user_id)
    @session_manager = Tracks::SessionManager.new(user_id, session_id)
    @retry_count = retry_count

    return unless session_exists_and_ready?

    boundary_tracks_resolved = resolve_boundary_tracks
    finalize_session(boundary_tracks_resolved)
  rescue StandardError => e
    ExceptionReporter.call(e, "Failed to resolve boundaries for user #{user_id}")

    mark_session_failed(e.message)
  end

  private

  attr_reader :user, :session_manager, :retry_count

  def session_exists_and_ready?
    return false unless session_manager.session_exists?

    unless session_manager.all_chunks_completed?
      reschedule_boundary_resolution

      return false
    end

    true
  end

  def resolve_boundary_tracks
    boundary_detector = Tracks::BoundaryDetector.new(user)
    boundary_detector.resolve_cross_chunk_tracks
  end

  def finalize_session(_boundary_tracks_resolved)
    session_data = session_manager.get_session_data
    session_data['tracks_created']

    session_manager.mark_completed
  end

  def reschedule_boundary_resolution
    if retry_count >= MAX_RETRIES
      mark_session_failed("Max retries (#{MAX_RETRIES}) exceeded waiting for chunks to complete")
      return
    end

    # Exponential backoff: 30s, 60s, 120s, 240s, 300s (capped at 5 minutes)
    delay = [30.seconds * (2**retry_count), 5.minutes].min

    self.class.set(wait: delay).perform_later(user.id, session_manager.session_id, retry_count + 1)
  end

  def mark_session_failed(error_message)
    session_manager.mark_failed(error_message)
  end
end
