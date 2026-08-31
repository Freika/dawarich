# frozen_string_literal: true

class Families::LapseNotificationJob < ApplicationJob
  queue_as :families

  def perform(user_id, family_id)
    user = User.find_by(id: user_id)
    family = Family.find_by(id: family_id)

    return unless user && family

    user.with_lock do
      next if Families::LapseNotice.notified?(user)

      FamilyMailer.plan_lapsed(user, family).deliver_now
      Families::LapseNotice.mark(user)
    end
  end
end
