# frozen_string_literal: true

class Users::ResetPointsCounterJob < ApplicationJob
  queue_as :default

  def perform(user_id)
    User.where(id: user_id).update_all(
      'points_count = (SELECT COUNT(*) FROM points WHERE points.user_id = users.id)'
    )
  end
end
