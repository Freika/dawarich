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

    # Hard delete with transaction - all associations cascade via dependent: :destroy
    ActiveRecord::Base.transaction do
      user.destroy!
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
