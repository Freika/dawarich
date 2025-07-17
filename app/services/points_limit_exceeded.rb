# frozen_string_literal: true

class PointsLimitExceeded
  def initialize(user)
    @user = user
  end

  def call
    return false if DawarichSettings.self_hosted?
    return true if @user.tracked_points.count >= points_limit

    false
  end

  private

  def points_limit
    DawarichSettings::BASIC_PAID_PLAN_LIMIT
  end
end
