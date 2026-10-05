# frozen_string_literal: true

class Users::Digests::Yearly::EmailSendingJob < ApplicationJob
  queue_as :mailers
  OWNER_KEY = 'command:mail.digest.yearly'

  def perform(user_id, year)
    result = JobOwnership.with_owner(OWNER_KEY) { send_digest(user_id, year) }
    return unless result == :not_owner

    Users::Digests::MailCommands.forward(:yearly, user_id, year, nil,
                                         event_id: job_id, producer: self.class.name)
  end

  private

  def send_digest(user_id, year)
    user = find_user_or_skip(user_id) || return
    digest = user.digests.yearly.find_by(year: year)

    return unless user.safe_settings.yearly_digest_emails_enabled?
    return if digest.blank?
    return if digest.sent_at.present?
    return if digest.distance.to_i.zero?

    Users::Digests::MailCommands.enqueue do
      Users::DigestsMailer.with(user: user, digest: digest).year_end_digest.deliver_later
    end
    digest.update!(sent_at: Time.current)
  end
end
