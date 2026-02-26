# frozen_string_literal: true

class Users::Destroy
  attr_reader :user

  def initialize(user)
    @user = user
  end

  def call
    user_id = user.id
    user_email = user.email

    # Validate user can be deleted (not a family owner with other members)
    # Use direct queries to avoid association cache issues with soft-deleted users
    created_family = Family.find_by(creator_id: user_id)
    if created_family
      member_count = Family::Membership.where(family_id: created_family.id).count
      if member_count > 1
        error_message = 'Cannot delete user who owns a family with other members'
        Rails.logger.warn "#{error_message}: user_id=#{user_id}"
        user.errors.add(:base, error_message)
        raise ActiveRecord::RecordInvalid.new(user)
      end
    end

    cancel_scheduled_jobs

    # Purge ActiveStorage attachments before delete_all (which bypasses callbacks)
    purge_attachments_for('Import', user.imports)
    purge_attachments_for('Export', user.exports)
    purge_attachments_for('Points::RawDataArchive', user.raw_data_archives)

    ActiveRecord::Base.transaction do
      # Delete associated records first (dependent: :destroy associations)
      # IMPORTANT: Order matters due to foreign key constraints!

      user.points.delete_all
      user.imports.delete_all
      user.stats.delete_all
      user.exports.delete_all
      user.notifications.delete_all

      # Delete visits BEFORE areas (visits has FK to areas)
      user.visits.delete_all
      user.areas.delete_all

      user.places.delete_all
      user.tags.delete_all
      user.trips.delete_all
      user.tracks.delete_all
      user.raw_data_archives.delete_all
      user.digests.delete_all
      user.sent_family_invitations.delete_all if user.respond_to?(:sent_family_invitations)

      # Delete family associations (memberships before family due to FK)
      # Delete ALL family memberships for this user (using direct query to avoid association cache issues)
      Family::Membership.where(user_id: user.id).delete_all

      # If user created a family, delete all remaining memberships and the family
      created_family = Family.find_by(creator_id: user.id)
      if created_family
        # Delete all remaining memberships in the created family (other users' memberships)
        Family::Membership.where(family_id: created_family.id).delete_all
        # Then delete the family itself
        created_family.delete
      end

      # Hard delete the user (bypasses soft-delete, skips callbacks)
      user.delete
    end

    Rails.logger.info "User #{user_id} (#{user_email}) and all associated data deleted"

    cleanup_user_cache(user_id)

    true
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

  def purge_attachments_for(record_type, relation)
    ActiveStorage::Attachment
      .where(record_type: record_type, record_id: relation.select(:id))
      .find_each { |a| a.purge }
  rescue StandardError => e
    Rails.logger.warn "Failed to purge #{record_type} attachments: #{e.message}"
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
