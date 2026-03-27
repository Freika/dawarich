# frozen_string_literal: true

class Map::ResidencyController < ApplicationController
  before_action :authenticate_user!
  before_action :require_pro!

  def show
    year = params[:year]&.to_i || default_year
    result = Residency::DayCounter.new(current_user, year).call

    @year = result[:year]
    @available_years = result[:available_years]
    @days_in_year = result[:days_in_year]
    @total_tracked_days = result[:total_tracked_days]
    @daily_countries = result[:daily_countries]
    @countries = result[:countries]

    render layout: false
  end

  private

  def default_year
    current_user.stats.maximum(:year) || Time.current.year
  end
end
