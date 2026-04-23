# frozen_string_literal: true

class Users::Digests::Monthly::EmailSendingJob < ApplicationJob
  queue_as :mailers

  def perform(user_id, year, month)
    user = find_user_or_skip(user_id) || return
    digest = user.digests.monthly.find_by(year: year, month: month)

    return unless user.safe_settings.monthly_digest_emails_enabled?
    return if digest.blank?
    return if digest.sent_at.present?
    return if digest.distance.to_i.zero?

    Users::DigestsMailer.with(user: user, digest: digest).monthly_digest.deliver_later
    digest.update!(sent_at: Time.current)
  end
end
