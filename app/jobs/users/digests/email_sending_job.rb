# frozen_string_literal: true

class Users::Digests::EmailSendingJob < ApplicationJob
  queue_as :mailers

  def perform(user_id, year)
    user = find_non_deleted_user(user_id)
    return unless user

    digest = user.digests.yearly.find_by(year: year)

    return unless should_send_email?(user, digest)

    Users::DigestsMailer.with(user: user, digest: digest).year_end_digest.deliver_later

    digest.update!(sent_at: Time.current)
  end

  private

  def should_send_email?(user, digest)
    return false unless user.safe_settings.digest_emails_enabled?
    return false if digest.blank?
    return false if digest.sent_at.present?

    true
  end
end
