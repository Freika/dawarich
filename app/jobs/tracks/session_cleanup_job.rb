# frozen_string_literal: true

# Background job for cleaning up track generation sessions
# Handles expired sessions, stuck sessions, and general maintenance
class Tracks::SessionCleanupJob < ApplicationJob
  queue_as :maintenance

  def perform
    Rails.logger.info "Starting track generation session cleanup"

    expired_cleaned = cleanup_expired_sessions
    stuck_cleaned = cleanup_stuck_sessions
    
    Rails.logger.info "Session cleanup completed: #{expired_cleaned} expired, #{stuck_cleaned} stuck sessions cleaned"
  rescue StandardError => e
    ExceptionReporter.call(e, 'Failed to cleanup track generation sessions')
    Rails.logger.error "Session cleanup failed: #{e.message}"
  end

  private

  def cleanup_expired_sessions
    # Rails cache handles TTL automatically, but we can still clean up
    # any sessions that might have been missed
    Tracks::SessionManager.cleanup_expired_sessions
  end

  def cleanup_stuck_sessions
    stuck_sessions = find_stuck_sessions
    return 0 if stuck_sessions.empty?

    Rails.logger.warn "Found #{stuck_sessions.size} stuck track generation sessions"

    cleaned_count = 0
    stuck_sessions.each do |session_info|
      if cleanup_stuck_session(session_info)
        cleaned_count += 1
      end
    end

    cleaned_count
  end

  def find_stuck_sessions
    stuck_sessions = []
    threshold = 4.hours.ago

    # Since we're using Rails.cache, we need to scan for stuck sessions differently
    # We'll look for sessions that are still in 'processing' state but very old
    # This is a simplified approach - in production you might want more sophisticated detection
    
    # For now, return empty array since Rails.cache doesn't provide easy key scanning
    # In a real implementation, you might want to:
    # 1. Store session keys in a separate tracking mechanism
    # 2. Use Redis directly for better key management
    # 3. Add session heartbeats for stuck detection
    
    stuck_sessions
  end

  def cleanup_stuck_session(session_info)
    session_manager = Tracks::SessionManager.new(session_info[:user_id], session_info[:session_id])
    
    session_data = session_manager.get_session_data
    return false unless session_data
    
    # Mark session as failed
    session_manager.mark_failed("Session stuck - cleaned up by maintenance job")
    
    # Notify user if configured
    if DawarichSettings.self_hosted?
      user = User.find_by(id: session_info[:user_id])
      notify_user_of_cleanup(user) if user
    end
    
    Rails.logger.info "Cleaned up stuck session #{session_info[:session_id]} for user #{session_info[:user_id]}"
    true
  rescue StandardError => e
    Rails.logger.error "Failed to cleanup stuck session #{session_info[:session_id]}: #{e.message}"
    false
  end

  def notify_user_of_cleanup(user)
    Notifications::Create.new(
      user: user,
      kind: :warning,
      title: 'Track Generation Interrupted',
      content: 'Your track generation process was interrupted and has been cleaned up. You may need to restart the generation manually.'
    ).call
  rescue StandardError => e
    Rails.logger.error "Failed to notify user #{user.id} about session cleanup: #{e.message}"
  end
end