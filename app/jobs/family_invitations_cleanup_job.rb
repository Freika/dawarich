# frozen_string_literal: true

class FamilyInvitationsCleanupJob < ApplicationJob
  queue_as :default

  def perform
    Rails.logger.info 'Starting family invitations cleanup'

    # Update expired invitations
    expired_count = FamilyInvitation.where(status: :pending)
                                    .where('expires_at < ?', Time.current)
                                    .update_all(status: :expired)

    Rails.logger.info "Updated #{expired_count} expired family invitations"

    # Delete old expired/cancelled invitations (older than 30 days)
    cleanup_threshold = 30.days.ago
    deleted_count = FamilyInvitation.where(status: [:expired, :cancelled])
                                    .where('updated_at < ?', cleanup_threshold)
                                    .delete_all

    Rails.logger.info "Deleted #{deleted_count} old family invitations"

    Rails.logger.info 'Family invitations cleanup completed'
  end
end