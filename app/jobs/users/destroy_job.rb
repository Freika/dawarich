# frozen_string_literal: true

class Users::DestroyJob < ApplicationJob
  queue_as :default

  sidekiq_options retry: false  # No retry for destructive operations

  def perform(user_id)
    user = User.deleted_accounts.find_by(id: user_id)

    unless user
      Rails.logger.warn "User #{user_id} not found or not marked for deletion, skipping"
      return
    end

    Rails.logger.info "Starting hard deletion for user #{user.id} (#{user.email})"

    Users::Destroy.new(user).call

    Rails.logger.info "Successfully deleted user #{user_id}"
  rescue ActiveRecord::RecordNotFound
    Rails.logger.warn "User #{user_id} not found, may have already been deleted"
  rescue StandardError => e
    Rails.logger.error "Failed to delete user #{user_id}: #{e.message}"
    ExceptionReporter.call(e, "User deletion failed for user_id #{user_id}")
    # Don't raise - leave user in deleted state for manual cleanup
  end
end
