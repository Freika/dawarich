# frozen_string_literal: true

class Users::MailerSendingJob < ApplicationJob
  queue_as :mailers

  def perform(user_id, email_type, **options)
    user = find_non_deleted_user(user_id)
    return unless user

    return if should_skip_email?(user, email_type)

    params = { user: user }.merge(options)

    UsersMailer.with(params).public_send(email_type).deliver_later
  end

  private

  def should_skip_email?(user, email_type)
    case email_type.to_s
    when 'trial_expires_soon', 'trial_expired'
      user.active?
    when 'post_trial_reminder_early', 'post_trial_reminder_late'
      user.active? || !user.trial?
    else
      false
    end
  end
end
