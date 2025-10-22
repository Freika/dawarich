# frozen_string_literal: true

class Digests::Queries::AllTime
  def initialize(user)
    @user = user
  end

  def call
    {
      total_countries: @user.points.where.not(country_name: nil).distinct.count(:country_name),
      total_cities: @user.points.where.not(city: nil).distinct.count(:city),
      total_places: @user.visits.joins(:area).distinct.count('areas.id'),
      total_distance_km: calculate_total_distance,
      account_age_days: account_age_days,
      first_point_date: first_point_date
    }
  end

  private

  def calculate_total_distance
    # Use cached stat data if available, otherwise calculate
    @user.stats.sum(:distance) || 0
  end

  def account_age_days
    (Date.today - @user.created_at.to_date).to_i
  end

  def first_point_date
    first_point = @user.points.order(timestamp: :asc).first
    first_point ? Time.at(first_point.timestamp).to_date : nil
  end
end
