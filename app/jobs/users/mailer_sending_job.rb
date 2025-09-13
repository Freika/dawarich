# frozen_string_literal: true

class Users::MailerSendingJob < ApplicationJob
  queue_as :mailers

  def perform(user_id, email_type, **options)
    user = User.find(user_id)

    if should_skip_email?(user, email_type)
      Rails.logger.info "Skipping #{email_type} email for user #{user_id} - #{skip_reason(user, email_type)}"
      return
    end

    params = { user: user }.merge(options)

    UsersMailer.with(params).public_send(email_type).deliver_later
  rescue ActiveRecord::RecordNotFound
    Rails.logger.warn "User with ID #{user_id} not found. Skipping #{email_type} email."
  end

  private

  def should_skip_email?(user, email_type)
    case email_type.to_s
    when 'trial_expires_soon', 'trial_expired'
      user.active?
    when 'post_trial_reminder_early', 'post_trial_reminder_late'
      user.active? || !user.trial?
    when 'subscription_expires_soon_early', 'subscription_expires_soon_late'
      !user.active? || !user.active_until&.future?
    when 'subscription_expired_early', 'subscription_expired_late'
      user.active? || user.active_until&.future? || user.trial?
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
    when 'subscription_expires_soon_early', 'subscription_expires_soon_late'
      'user is not active or subscription already expired'
    when 'subscription_expired_early', 'subscription_expired_late'
      'user is active, subscription not expired, or user is in trial'
    else
      'unknown reason'
    end
  end
end
