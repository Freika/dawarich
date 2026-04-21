# frozen_string_literal: true

class Users::MailerSendingJob < ApplicationJob
  queue_as :mailers

  REVERSE_TRIAL_EMAIL_TYPES = %w[
    trial_first_payment_soon
    trial_converted
    pending_payment_day_1
    pending_payment_day_3
    pending_payment_day_7
  ].freeze

  def perform(user_id, email_type, **options)
    user = find_user_or_skip(user_id) || return

    return if should_skip_email?(user, email_type)

    params = { user: user }.merge(options)

    mailer_class = mailer_class_for(email_type)

    unless mailer_class&.respond_to?(email_type)
      Rails.logger.warn("[MailerSendingJob] unknown email_type=#{email_type} user_id=#{user.id}")
      return
    end

    mailer_class.with(params).public_send(email_type).deliver_later
  end

  private

  def mailer_class_for(email_type)
    if REVERSE_TRIAL_EMAIL_TYPES.include?(email_type.to_s)
      Users::ReverseTrialMailer
    else
      UsersMailer
    end
  end

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
