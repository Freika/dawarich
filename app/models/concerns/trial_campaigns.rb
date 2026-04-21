# frozen_string_literal: true

# Handles scheduled email campaigns tied to the trial lifecycle.
#
# Campaigns:
#   - product emails        (welcome, explore_features)
#   - legacy trial emails   (trial_expires_soon, trial_expired, post_trial_reminder_*)
#   - paddle billing emails (trial_first_payment_soon, trial_converted, post_trial_reminder_*)
#
# The legacy campaign fires for any new cloud signup. If that user later completes
# a Paddle checkout we still do not want them to keep receiving the legacy expiry
# emails - #cancel_legacy_trial_emails flips a settings flag. The MailerSendingJob
# (owned by another agent) checks #legacy_trial_mail_cancelled? before sending any
# legacy trial email.
module TrialCampaigns
  extend ActiveSupport::Concern

  def schedule_product_emails
    Users::MailerSendingJob.perform_later(id, 'welcome')
    Users::MailerSendingJob.set(wait: 2.days).perform_later(id, 'explore_features')
  end

  # Paddle-billing emails are only relevant for users who went through the
  # reverse-trial Paddle checkout flow. Existing users who receive a plan-change
  # callback (their subscription_source flipped to :paddle via the manager
  # callback) must NOT get "first payment in 5 days" emails.
  def schedule_paddle_billing_emails
    return unless sub_source_paddle?
    return unless signup_variant == 'reverse_trial'

    Users::MailerSendingJob.set(wait: 5.days).perform_later(id, 'trial_first_payment_soon')
    Users::MailerSendingJob.set(wait: 7.days).perform_later(id, 'trial_converted')
    Users::MailerSendingJob.set(wait: 9.days).perform_later(id, 'post_trial_reminder_early')
    Users::MailerSendingJob.set(wait: 14.days).perform_later(id, 'post_trial_reminder_late')
  end

  def schedule_legacy_trial_emails
    Users::MailerSendingJob.set(wait: 5.days).perform_later(id, 'trial_expires_soon')
    Users::MailerSendingJob.set(wait: 7.days).perform_later(id, 'trial_expired')
    Users::MailerSendingJob.set(wait: 9.days).perform_later(id, 'post_trial_reminder_early')
    Users::MailerSendingJob.set(wait: 14.days).perform_later(id, 'post_trial_reminder_late')
  end

  # Cancels pending legacy trial emails by flipping a flag that the mailer job
  # (Users::MailerSendingJob, owned by another agent) checks before sending.
  #
  # TODO(mailer-agent): Users::MailerSendingJob needs to early-return when the
  # email_type is a legacy trial email and user.legacy_trial_mail_cancelled? is true.
  def cancel_legacy_trial_emails
    new_settings = settings.merge(
      'legacy_trial_cancelled' => true,
      'legacy_trial_cancelled_at' => Time.current.iso8601
    )
    update!(settings: new_settings)
  end

  def legacy_trial_mail_cancelled?
    settings['legacy_trial_cancelled'] == true
  end
end
