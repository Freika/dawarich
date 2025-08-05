# frozen_string_literal: true

# Service for cleaning up track generation sessions and maintenance tasks
# Provides utilities for session management and cleanup operations
class Tracks::SessionCleanup
  class << self
    # Schedule regular cleanup job
    def schedule_cleanup
      Tracks::SessionCleanupJob.perform_later
    end

    # Manual cleanup of all sessions for a user (e.g., when user is deleted)
    def cleanup_user_sessions(user_id)
      Rails.logger.info "Cleaning up all sessions for user #{user_id}"
      
      cleaned_count = 0
      
      # Since we can't easily scan Rails.cache keys, we'll rely on TTL cleanup
      # In a production setup, you might want to maintain a separate index of active sessions
      
      Rails.logger.info "Cleaned up #{cleaned_count} sessions for user #{user_id}"
      cleaned_count
    end

    # Force cleanup of a specific session
    def cleanup_session(user_id, session_id)
      session_manager = Tracks::SessionManager.new(user_id, session_id)
      
      if session_manager.session_exists?
        session_manager.cleanup_session
        Rails.logger.info "Force cleaned session #{session_id} for user #{user_id}"
        true
      else
        Rails.logger.warn "Session #{session_id} not found for user #{user_id}"
        false
      end
    end

    # Get session statistics (for monitoring)
    def session_statistics
      # With Rails.cache, we can't easily get detailed statistics
      # This is a limitation of using Rails.cache vs direct Redis access
      # In production, consider maintaining separate session tracking
      
      {
        total_sessions: 0, # Can't count easily with Rails.cache
        processing_sessions: 0,
        completed_sessions: 0,
        failed_sessions: 0,
        cleanup_performed_at: Time.current
      }
    end

    # Health check for session management system
    def health_check
      begin
        # Test session creation and cleanup
        test_user_id = 'health_check_user'
        test_session = Tracks::SessionManager.create_for_user(test_user_id, { test: true })
        
        # Verify session exists
        session_exists = test_session.session_exists?
        
        # Cleanup test session
        test_session.cleanup_session
        
        {
          status: session_exists ? 'healthy' : 'unhealthy',
          cache_accessible: true,
          timestamp: Time.current
        }
      rescue StandardError => e
        {
          status: 'unhealthy',
          cache_accessible: false,
          error: e.message,
          timestamp: Time.current
        }
      end
    end
  end
end