# frozen_string_literal: true

class Families::LapseNotificationJob < ApplicationJob
  queue_as :families

  self.enqueue_after_transaction_commit = true
  OWNERSHIP_KEY = 'command:mail.family_lapse'

  def perform(user_id, family_id)
    return forward(user_id, family_id) if JobOwnership.with_owner(OWNERSHIP_KEY) { true } == :not_owner

    user = User.find_by(id: user_id)
    family = Family.find_by(id: family_id)

    return unless user && family
    return unless claim(user)

    begin
      FamilyMailer.plan_lapsed(user, family).deliver_now
    rescue StandardError
      Families::LapseNotice.clear(user)
      raise
    end
  end

  private

  def forward(user_id, family_id)
    lapse_at = Family.find_by(id: family_id)&.access_until&.utc&.iso8601 || 'none'
    JobCommands.forward('mail.family_lapse', {
                          'user_id' => user_id,
                          'family_id' => family_id,
                          'locale' => I18n.locale.to_s,
                          'lapse_at' => lapse_at
                        }, event_id: job_id, aggregate_id: user_id, producer: self.class.name,
                           dedupe_key: "family-lapse:#{family_id}:#{user_id}:#{lapse_at}")
  end

  def claim(user)
    user.with_lock do
      next false if Families::LapseNotice.notified?(user)

      Families::LapseNotice.mark(user)
      true
    end
  end
end
