# frozen_string_literal: true

class Users::DestroyJob < ApplicationJob
  queue_as :default

  sidekiq_options retry: 3

  def perform(user_id)
    user = User.deleted.find_by(id: user_id)

    unless user
      Rails.logger.info "#{self.class.name}: User #{user_id} not found among soft-deleted users, skipping"
      return
    end

    Rails.logger.info "Starting hard deletion for user #{user.id} (#{user.email})"

    Users::Destroy.new(user).call

    Rails.logger.info "Successfully deleted user #{user_id}"
  rescue ActiveRecord::RecordInvalid => e
    # User cannot be deleted (e.g., owns a family with members) — not transient, retrying won't help
    Rails.logger.error "User deletion blocked for user_id #{user_id}: #{e.message}"
    ExceptionReporter.call(e, "User deletion blocked for user_id #{user_id}")
  rescue StandardError => e
    ExceptionReporter.call(e, "User deletion failed for user_id #{user_id}")
    raise
  end
end
