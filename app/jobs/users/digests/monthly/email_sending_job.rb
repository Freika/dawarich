# frozen_string_literal: true

class Users::Digests::Monthly::EmailSendingJob < ApplicationJob
  queue_as :mailers
  OWNER_KEY = 'command:mail.digest.monthly'

  def perform(user_id, year, month)
    if JobOwnership.oban?(OWNER_KEY)
      return Users::Digests::MailCommands.forward(:monthly, user_id, year, month,
                                                  event_id: job_id, producer: self.class.name)
    end

    send_digest(user_id, year, month)
  end

  private

  def send_digest(user_id, year, month)
    user = find_user_or_skip(user_id) || return
    digest = user.digests.monthly.find_by(year: year, month: month)

    return unless user.safe_settings.monthly_digest_emails_enabled?
    return if digest.blank?
    return if digest.sent_at.present?
    return if digest.distance.to_i.zero?

    Users::Digests::MailCommands.enqueue do
      Users::DigestsMailer.with(user: user, digest: digest).monthly_digest.deliver_later
    end
    digest.update!(sent_at: Time.current)
  end
end
