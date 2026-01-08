# frozen_string_literal: true

class Users::DestroyJob < ApplicationJob
  queue_as :default

  sidekiq_options retry: false

  def perform(user_id)
    user = User.deleted_accounts.find_by(id: user_id)

    return unless user

    Rails.logger.info "Starting hard deletion for user #{user.id} (#{user.email})"

    Users::Destroy.new(user).call

    Rails.logger.info "Successfully deleted user #{user_id}"
  rescue ActiveRecord::RecordNotFound
    Rails.logger.warn "User #{user_id} not found, may have already been deleted"
  rescue StandardError => e
    ExceptionReporter.call(e, "User deletion failed for user_id #{user_id}")
  end
end
