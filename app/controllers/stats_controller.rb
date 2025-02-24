# frozen_string_literal: true

class StatsController < ApplicationController
  before_action :authenticate_user!
  before_action :authenticate_active_user!, only: %i[update update_all]

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
    if params[:month] == 'all'
      (1..12).each do |month|
        Stats::CalculatingJob.perform_later(current_user.id, params[:year], month)
      end

      target = "the whole #{params[:year]}"
    else
      Stats::CalculatingJob.perform_later(current_user.id, params[:year], params[:month])

      target = "#{Date::MONTHNAMES[params[:month].to_i]} of #{params[:year]}"
    end

    redirect_to stats_path, notice: "Stats for #{target} are being updated", status: :see_other
  end

  def update_all
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
