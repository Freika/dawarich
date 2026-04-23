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
    'welcome'              => ['UsersMailer', :welcome],
    'explore_features'     => ['UsersMailer', :explore_features],
    'archival_approaching' => ['UsersMailer', :archival_approaching],
    'oauth_account_link'   => ['UsersMailer', :oauth_account_link]
  }.freeze

  def perform(user_id, email_type, **options)
    user = find_user_or_skip(user_id) || return

    mailer_class_name, action = MAILER_REGISTRY.fetch(email_type.to_s) do
      raise UnknownEmailType, "Unknown email_type=#{email_type.inspect} user_id=#{user.id}"
    end

    params = { user: user }.merge(options)
    mailer_class_name.constantize.with(params).public_send(action).deliver_later
  end
end
