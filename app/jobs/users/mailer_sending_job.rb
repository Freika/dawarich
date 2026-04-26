# frozen_string_literal: true

class Users::MailerSendingJob < ApplicationJob
  queue_as :mailers

  class UnknownEmailType < StandardError; end

  MAILER_REGISTRY = {
    'welcome'              => ['UsersMailer', :welcome],
    'explore_features'     => ['UsersMailer', :explore_features],
    'archival_approaching' => ['UsersMailer', :archival_approaching]
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
