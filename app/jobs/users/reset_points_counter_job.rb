# frozen_string_literal: true

class Users::ResetPointsCounterJob < ApplicationJob
  queue_as :default

  def perform(user_id)
    User.reset_counters(user_id, :points)
  end
end
