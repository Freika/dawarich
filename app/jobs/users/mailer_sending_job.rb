# frozen_string_literal: true

class Users::MailerSendingJob < ApplicationJob
  queue_as :mailers

  class UnknownEmailType < StandardError; end

  # Trial-reminder entries below are kept transitionally so stale Sidekiq
  # jobs scheduled before the billing extraction drain cleanly. New code
  # must NOT enqueue these — Manager owns the trial-reminder lifecycle now.
  # Earliest safe removal: 2026-05-17 (deploy + 21 days, after the longest
  # `wait: 14.days` reminder fires for any pre-deploy signup).
  MAILER_REGISTRY = {
    'welcome'                  => ['UsersMailer', :welcome],
    'explore_features'         => ['UsersMailer', :explore_features],
    'archival_approaching'     => ['UsersMailer', :archival_approaching],
    'trial_expires_soon'       => ['UsersMailer', :trial_expires_soon],
    'trial_expired'            => ['UsersMailer', :trial_expired],
    'post_trial_reminder_early' => ['UsersMailer', :post_trial_reminder_early],
    'post_trial_reminder_late' => ['UsersMailer', :post_trial_reminder_late],
    'oauth_account_link'       => ['UsersMailer', :oauth_account_link],
    'account_destroy_confirmation' => ['UsersMailer', :account_destroy_confirmation]
  }.freeze

  def perform(user_id, email_type, **options)
    user = find_user_or_skip(user_id) || return
    return if should_skip_email?(user, email_type)

    mailer_class_name, action = MAILER_REGISTRY.fetch(email_type.to_s) do
      raise UnknownEmailType, "Unknown email_type=#{email_type.inspect} user_id=#{user.id}"
    end

    params = { user: user }.merge(options)
    mailer_class_name.constantize.with(params).public_send(action).deliver_later
  end

  private

  # Suppress trial-reminder emails for users who upgraded / converted
  # between when the job was scheduled and when it fires. Otherwise an
  # active subscriber gets "your trial expires in 2 days" — a classic
  # support-ticket generator.
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
