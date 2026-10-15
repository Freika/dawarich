# frozen_string_literal: true

class Map::ResidencyController < ApplicationController
  before_action :authenticate_user!
  before_action :require_pro!

  def show
    year = params[:year]&.to_i || Residency::DayCounter.default_year(current_user)
    result = Residency::DayCounter.new(current_user, year).call

    @year = result[:year]
    @available_years = result[:available_years]
    @days_in_year = result[:days_in_year]
    @total_tracked_days = result[:total_tracked_days]
    @daily_countries = result[:daily_countries]
    @countries = result[:countries]
    @activity = Insights::ActivityHeatmapCalculator.new(
      current_user.scoped_stats.where(year: @year, month: 1..12), @year
    ).call
    @distance_race = Insights::DistanceRace.for(current_user, @year)

    render layout: false
  end
end
