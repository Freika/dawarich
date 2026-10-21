# frozen_string_literal: true

class Users::MailerSendingJob < ApplicationJob
  queue_as :mailers

  class UnknownEmailType < StandardError; end

  EXPLORE_FEATURES_KEY = 'command:users.explore_features_mail'

  MAILER_REGISTRY = {
    'welcome'                     => ['UsersMailer', :welcome],
    'explore_features'            => ['UsersMailer', :explore_features],
    'archival_approaching'        => ['UsersMailer', :archival_approaching],
    'oauth_account_link'          => ['UsersMailer', :oauth_account_link],
    'account_destroy_confirmation' => ['UsersMailer', :account_destroy_confirmation]
  }.freeze

  LEGACY_MANAGER_EMAIL_TYPES = %w[
    trial_expired
    trial_expires_soon
    post_trial_reminder_early
    post_trial_reminder_late
  ].freeze

  def perform(user_id, email_type, **options)
    type = email_type.to_s
    return explore_features(user_id, type, options) if type == 'explore_features'
    return send_mail(user_id, type, options) unless UserMailCommands::TYPES.key?(type)

    key = "command:#{UserMailCommands::TYPES.fetch(type)}"
    result = JobOwnership.with_owner(key) { send_mail(user_id, type, options) }
    forward(user_id, type, options) if result == :not_owner
  end

  private

  def send_mail(user_id, email_type, options)
    user = find_user_or_skip(user_id) || return

    if LEGACY_MANAGER_EMAIL_TYPES.include?(email_type.to_s)
      Rails.logger.info(
        "[Users::MailerSendingJob] skipping legacy Manager-owned email_type=#{email_type} user_id=#{user.id}"
      )
      return
    end

    mailer_class_name, action = MAILER_REGISTRY.fetch(email_type.to_s) do
      raise UnknownEmailType, "Unknown email_type=#{email_type.inspect} user_id=#{user.id}"
    end

    params = { user: user }.merge(options)
    mailer_class_name.constantize.with(params).public_send(action).deliver_later
  end

  def explore_features(user_id, type, options)
    result = JobOwnership.with_owner(EXPLORE_FEATURES_KEY) { send_mail(user_id, type, options) }
    forward_explore_features(user_id) if result == :not_owner
  end

  def forward(user_id, type, options)
    options = options.merge(epoch: archival_epoch(user_id)) if type == 'archival_approaching' && !options.key?(:epoch)
    UserMailCommands.forward(type, user_id, event_id: job_id, producer: self.class.name, **options)
  end

  def archival_epoch(user_id)
    User.find_by(id: user_id)&.settings&.dig('archival_warnings', '11_5mo').presence || Time.zone.now.iso8601
  end

  def forward_explore_features(user_id)
    JobCommands.forward('users.explore_features_mail', { 'user_id' => user_id, 'locale' => I18n.locale.to_s },
                        event_id: job_id, aggregate_id: user_id, producer: self.class.name)
  end
end
