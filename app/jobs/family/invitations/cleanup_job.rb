# frozen_string_literal: true

class Family::Invitations::CleanupJob < ApplicationJob
  queue_as :families

  # Runs on every instance: invitations belong to individual families, so there
  # is no instance-wide flag to check. Expiring nothing is a cheap no-op.
  def perform
    Rails.logger.info 'Starting family invitations cleanup'

    expired_count = Family::Invitation.where(status: :pending)
                                      .where('expires_at < ?', Time.current)
                                      .update_all(status: :expired)

    Rails.logger.info "Updated #{expired_count} expired family invitations"

    cleanup_threshold = 30.days.ago
    deleted_count =
      Family::Invitation.where(status: %i[expired cancelled])
                        .where('updated_at < ?', cleanup_threshold)
                        .delete_all

    Rails.logger.info "Deleted #{deleted_count} old family invitations"

    Rails.logger.info 'Family invitations cleanup completed'
  end
end
