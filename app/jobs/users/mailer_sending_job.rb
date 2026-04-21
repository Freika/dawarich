# frozen_string_literal: true

class Users::MailerSendingJob < ApplicationJob
  queue_as :mailers

  class UnknownEmailType < StandardError; end

  # Explicit routing registry: email_type => [mailer_class_name, action_name]
  #
  # Kept as strings to avoid autoload issues at class-body evaluation and so
  # unknown types produce a clear `UnknownEmailType` error instead of a silent
  # `NoMethodError` in production. Add new email types here — don't rely on
  # `respond_to?` reflection.
  MAILER_REGISTRY = {
    # UsersMailer
    'welcome'                   => ['UsersMailer', :welcome],
    'explore_features'          => ['UsersMailer', :explore_features],
    'trial_expires_soon'        => ['UsersMailer', :trial_expires_soon],
    'trial_expired'             => ['UsersMailer', :trial_expired],
    'post_trial_reminder_early' => ['UsersMailer', :post_trial_reminder_early],
    'post_trial_reminder_late'  => ['UsersMailer', :post_trial_reminder_late],
    'archival_approaching'      => ['UsersMailer', :archival_approaching],

    # Users::ReverseTrialMailer
    'trial_first_payment_soon'  => ['Users::ReverseTrialMailer', :trial_first_payment_soon],
    'trial_converted'           => ['Users::ReverseTrialMailer', :trial_converted],
    'pending_payment_day_1'     => ['Users::ReverseTrialMailer', :pending_payment_day_1],
    'pending_payment_day_3'     => ['Users::ReverseTrialMailer', :pending_payment_day_3],
    'pending_payment_day_7'     => ['Users::ReverseTrialMailer', :pending_payment_day_7]
  }.freeze

  def perform(user_id, email_type, **options)
    user = find_user_or_skip(user_id) || return

    # Coordination: the user.rb agent is adding `legacy_trial_mail_cancelled?`
    # so users who converted/cancelled legacy trials don't get re-nagged by any
    # `trial_*` mailer. Check defensively with respond_to? until that lands.
    if email_type.to_s.start_with?('trial_') &&
       user.respond_to?(:legacy_trial_mail_cancelled?) &&
       user.legacy_trial_mail_cancelled?
      return
    end

    return if should_skip_email?(user, email_type)

    mailer_class_name, action = MAILER_REGISTRY.fetch(email_type.to_s) do
      raise UnknownEmailType, "Unknown email_type=#{email_type.inspect} user_id=#{user.id}"
    end

    params = { user: user }.merge(options)
    mailer_class_name.constantize.with(params).public_send(action).deliver_later
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
