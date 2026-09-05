# frozen_string_literal: true

class Families::LapseNotificationJob < ApplicationJob
  queue_as :families

  self.enqueue_after_transaction_commit = true

  def perform(user_id, family_id)
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

  def claim(user)
    user.with_lock do
      next false if Families::LapseNotice.notified?(user)

      Families::LapseNotice.mark(user)
      true
    end
  end
end
