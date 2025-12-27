# frozen_string_literal: true

class YearlyDigests::EmailSendingJob < ApplicationJob
  queue_as :mailers

  def perform(user_id, year)
    user = User.find(user_id)
    digest = user.yearly_digests.yearly.find_by(year: year)

    return unless should_send_email?(user, digest)

    YearlyDigestsMailer.with(user: user, digest: digest).year_end_digest.deliver_later

    digest.update!(sent_at: Time.current)
  rescue ActiveRecord::RecordNotFound
    ExceptionReporter.call(
      'YearlyDigests::EmailSendingJob',
      "User with ID #{user_id} not found. Skipping year-end digest email."
    )
  end

  private

  def should_send_email?(user, digest)
    return false unless user.safe_settings.digest_emails_enabled?
    return false unless digest.present?
    return false if digest.sent_at.present? # Already sent

    true
  end
end
