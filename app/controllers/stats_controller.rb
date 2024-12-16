# frozen_string_literal: true

class StatsController < ApplicationController
  before_action :authenticate_user!

  def index
    @stats = current_user.stats.group_by(&:year).sort.reverse
    @points_total = current_user.tracked_points.count
    @points_reverse_geocoded = current_user.total_reverse_geocoded_points
    @points_reverse_geocoded_without_data = current_user.total_reverse_geocoded_points_without_data
  end

  def show
    @year = params[:year].to_i
    @stats = current_user.stats.where(year: @year).order(:month)
  end

  def update
    current_user.years_tracked.each do |year|
      year[:months].each do |month|
        Stats::CalculatingJob.perform_later(
          current_user.id, year[:year], Date::ABBR_MONTHNAMES.index(month)
        )
      end
    end

    redirect_to stats_path, notice: 'Stats are being updated', status: :see_other
  end
end
