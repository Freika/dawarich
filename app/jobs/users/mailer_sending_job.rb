# frozen_string_literal: true

class Users::MailerSendingJob < ApplicationJob
  queue_as :mailers

  def perform(user_id, email_type, **options)
    user = User.find(user_id)

    params = { user: user }.merge(options)

    UsersMailer.with(params).public_send(email_type).deliver_later
  end
end
