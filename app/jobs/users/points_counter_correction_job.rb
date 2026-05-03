# frozen_string_literal: true

class Users::PointsCounterCorrectionJob < ApplicationJob
  queue_as :low_priority

  def perform
    User.active_or_trial.find_each do |user|
      actual_count = user.points.count
      next if user.points_count == actual_count

      user.update_column(:points_count, actual_count)
    end
  end
end
