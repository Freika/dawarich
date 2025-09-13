# frozen_string_literal: true

class Users::MailerSendingJob < ApplicationJob
  queue_as :mailers

  def perform(user_id, email_type, **options)
    user = User.find(user_id)

    if should_skip_email?(user, email_type)
      ExceptionReporter.call(
        'Users::MailerSendingJob',
        "Skipping #{email_type} email for user ID #{user_id} - #{skip_reason(user, email_type)}"
      )

      return
    end

    params = { user: user }.merge(options)

    UsersMailer.with(params).public_send(email_type).deliver_later
  rescue ActiveRecord::RecordNotFound
    ExceptionReporter.call(
      'Users::MailerSendingJob',
      "User with ID #{user_id} not found. Skipping #{email_type} email."
    )
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

  def skip_reason(user, email_type)
    case email_type.to_s
    when 'trial_expires_soon', 'trial_expired'
      'user is already subscribed'
    when 'post_trial_reminder_early', 'post_trial_reminder_late'
      user.active? ? 'user is subscribed' : 'user is not in trial state'
    else
      'unknown reason'
    end
  end
end
