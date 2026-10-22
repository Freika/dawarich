# frozen_string_literal: true

class PointsLimitExceeded
  def initialize(user)
    @user = user
    @entitlements = Entitlements.for(user)
  end

  def call
    return false if @entitlements.unlimited_points?

    Rails.cache.fetch(cache_key, expires_in: 1.day) do
      @user.points_count.to_i >= points_limit
    end
  end

  private

  def cache_key
    "points_limit_exceeded/#{@user.id}"
  end

  def points_limit
    @entitlements.points_limit
  end
end
