# frozen_string_literal: true

class StatsController < ApplicationController
  before_action :authenticate_user!
  before_action :authenticate_active_user!, only: %i[update update_all]

  def index
    @stats = build_stats
    assign_points_statistics
    @year_distances = precompute_year_distances
  end

  def show
    @year = params[:year].to_i
    @stats = current_user.stats.where(year: @year).order(:month)
    @year_distances = { @year => Stat.year_distance(@year, current_user) }
  end

  def month
    @year = params[:year].to_i
    @month = params[:month].to_i
    @stat = current_user.stats.find_by(year: @year, month: @month)
    @previous_stat = current_user.stats.find_by(year: @year, month: @month - 1) if @month > 1
    @average_distance_this_year = current_user.stats.where(year: @year).average(:distance).to_i / 1000
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

  private

  def assign_points_statistics
    points_stats = ::StatsQuery.new(current_user).points_stats

    @points_total = points_stats[:total]
    @points_reverse_geocoded = points_stats[:geocoded]
    @points_reverse_geocoded_without_data = points_stats[:without_data]
  end

  def precompute_year_distances
    year_distances = {}

    @stats.each do |year, stats|
      stats_by_month = stats.index_by(&:month)

      year_distances[year] = (1..12).map do |month|
        month_name = Date::MONTHNAMES[month]
        distance = stats_by_month[month]&.distance || 0

        [month_name, distance]
      end
    end

    year_distances
  end

  def build_stats
    current_user.stats.group_by(&:year).transform_values do |stats|
      stats.sort_by(&:updated_at).reverse
    end.sort.reverse
  end
end
