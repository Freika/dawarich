# frozen_string_literal: true

class Users::MailerSendingJob < ApplicationJob
  queue_as :mailers

  def perform(user_id, email_type, **options)
    user = User.find(user_id)

    if trial_related_email?(email_type) && user.active?
      Rails.logger.info "Skipping #{email_type} email for user #{user_id} - user is already subscribed"
      return
    end

    params = { user: user }.merge(options)

    UsersMailer.with(params).public_send(email_type).deliver_later
  end

  private

  def trial_related_email?(email_type)
    %w[trial_expires_soon trial_expired].include?(email_type.to_s)
  end
end
