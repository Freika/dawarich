# frozen_string_literal: true

# Resolves cross-chunk track boundaries and finalizes parallel track generation
# Runs after all chunk processors complete to handle tracks spanning multiple chunks
class Tracks::BoundaryResolverJob < ApplicationJob
  queue_as :tracks

  def perform(user_id, session_id)
    @user = User.find(user_id)
    @session_manager = Tracks::SessionManager.new(user_id, session_id)

    Rails.logger.info "Starting boundary resolution for user #{user_id} (session: #{session_id})"

    return unless session_exists_and_ready?

    boundary_tracks_resolved = resolve_boundary_tracks
    finalize_session(boundary_tracks_resolved)

    Rails.logger.info "Boundary resolution completed for user #{user_id}: #{boundary_tracks_resolved} boundary tracks resolved"

  rescue StandardError => e
    ExceptionReporter.call(e, "Failed to resolve boundaries for user #{user_id}")
    Rails.logger.error "Boundary resolution failed for user #{user_id}: #{e.message}"

    mark_session_failed(e.message)
  end

  private

  attr_reader :user, :session_manager

  def session_exists_and_ready?
    unless session_manager.session_exists?
      Rails.logger.warn "Session #{session_manager.session_id} not found for user #{user.id}, skipping boundary resolution"
      return false
    end

    unless session_manager.all_chunks_completed?
      Rails.logger.warn "Not all chunks completed for session #{session_manager.session_id}, rescheduling boundary resolution"
      reschedule_boundary_resolution
      return false
    end

    true
  end

  def resolve_boundary_tracks
    boundary_detector = Tracks::BoundaryDetector.new(user)
    boundary_detector.resolve_cross_chunk_tracks
  end

  def finalize_session(boundary_tracks_resolved)
    session_data = session_manager.get_session_data
    total_tracks = session_data['tracks_created'] + boundary_tracks_resolved

    session_manager.mark_completed
    create_success_notification(total_tracks)
  end

  def reschedule_boundary_resolution
    # Reschedule with exponential backoff (max 5 minutes)
    delay = [30.seconds, 1.minute, 2.minutes, 5.minutes].sample

    self.class.set(wait: delay).perform_later(user.id, session_manager.session_id)
    Rails.logger.info "Rescheduled boundary resolution for user #{user.id} in #{delay} seconds"
  end

  def mark_session_failed(error_message)
    session_manager.mark_failed(error_message)
    create_error_notification(error_message)
  end

  def create_success_notification(tracks_created)
    Notifications::Create.new(
      user: user,
      kind: :info,
      title: 'Track Generation Complete',
      content: "Generated #{tracks_created} tracks from your location data using parallel processing. Check your tracks section to view them."
    ).call
  end

  def create_error_notification(error_message)
    return unless DawarichSettings.self_hosted?

    Notifications::Create.new(
      user: user,
      kind: :error,
      title: 'Track Generation Failed',
      content: "Failed to complete track generation: #{error_message}"
    ).call
  end
end
