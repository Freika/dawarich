# frozen_string_literal: true

class PointsLimitExceeded
  def initialize(user)
    @user = user
  end

  def call
    return false if DawarichSettings.self_hosted?

    Rails.cache.fetch(cache_key, expires_in: 1.day) do
      @user.points_count.to_i >= points_limit
    end
  end

  private

  def cache_key
    "points_limit_exceeded/#{@user.id}"
  end

  def points_limit
    DawarichSettings::BASIC_PAID_PLAN_LIMIT
  end
end
