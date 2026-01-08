# frozen_string_literal: true

class Users::Destroy
  attr_reader :user

  def initialize(user)
    @user = user
  end

  def call
    user_id = user.id
    user_email = user.email

    cancel_scheduled_jobs

    ActiveRecord::Base.transaction do
      # Delete associated records first (dependent: :destroy associations)
      user.points.delete_all
      user.imports.delete_all
      user.stats.delete_all
      user.exports.delete_all
      user.notifications.delete_all
      user.areas.delete_all
      user.visits.delete_all
      user.places.delete_all
      user.tags.delete_all
      user.trips.delete_all
      user.tracks.delete_all
      user.raw_data_archives.delete_all
      user.digests.delete_all
      user.sent_family_invitations.delete_all if user.respond_to?(:sent_family_invitations)
      user.family_membership&.delete
      user.created_family&.delete

      # Hard delete the user (bypasses soft-delete, skips callbacks)
      user.delete
    end

    Rails.logger.info "User #{user_id} (#{user_email}) and all associated data deleted"

    cleanup_user_cache(user_id)

    true
  rescue StandardError => e
    Rails.logger.error "Error during user deletion: #{e.message}"
    ExceptionReporter.call(e, "User destroy service failed for user_id #{user_id}")
    raise
  end

  private

  def cancel_scheduled_jobs
    scheduled_set = Sidekiq::ScheduledSet.new

    jobs_cancelled = scheduled_set.select { |job|
      job.klass == 'Users::MailerSendingJob' && job.args.first == user.id
    }.map(&:delete).count

    Rails.logger.info "Cancelled #{jobs_cancelled} scheduled jobs for user #{user.id}"
  rescue StandardError => e
    Rails.logger.warn "Failed to cancel scheduled jobs for user #{user.id}: #{e.message}"
    ExceptionReporter.call(e, "Failed to cancel scheduled jobs during user deletion")
  end

  def cleanup_user_cache(user_id)
    cache_keys = [
      "dawarich/user_#{user_id}_countries_visited",
      "dawarich/user_#{user_id}_cities_visited",
      "dawarich/user_#{user_id}_total_distance",
      "dawarich/user_#{user_id}_years_tracked"
    ]

    cache_keys.each { |key| Rails.cache.delete(key) }

    Rails.logger.info "Cleared cache for user #{user_id}"
  rescue StandardError => e
    Rails.logger.warn "Failed to clear cache for user #{user_id}: #{e.message}"
  end
end
