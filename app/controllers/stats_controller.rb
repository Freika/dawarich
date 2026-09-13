# frozen_string_literal: true

class StatsController < ApplicationController
  before_action :authenticate_user!
  before_action :authenticate_active_user!, only: %i[update update_all]
  before_action :validate_update_period!, only: :update

  def index
    @stats = build_stats
    assign_points_statistics
    @year_distances = precompute_year_distances
    @locked_years = locked_years
  end

  def show
    @year = params[:year].to_i
    @stats = current_user.scoped_stats.where(year: @year).order(:month)
    @year_distances = { @year => Stat.year_distance(@year, current_user) }
  end

  def month
    @year = params[:year].to_i
    @month = params[:month].to_i
    @stat = current_user.scoped_stats.find_by(year: @year, month: @month)
    @previous_stat = current_user.scoped_stats.find_by(year: @year, month: @month - 1) if @month > 1
    @average_distance_this_year = current_user.scoped_stats.where(year: @year).average(:distance).to_i / 1000
    @sharing_allowed = current_user.full_access?
  end

  def update
    if params[:month] == 'all'
      (1..12).each do |month|
        Stats::CalculatingJob.perform_later(current_user.id, params[:year], month)
      end

      target = I18n.t('controllers.stats.whole_year', year: params[:year])
    else
      Stats::CalculatingJob.perform_later(current_user.id, params[:year], params[:month])

      month = I18n.l(Date.new(params[:year].to_i, params[:month].to_i, 1), format: :month_name)
      target = I18n.t('controllers.stats.month_of_year', month:, year: params[:year])
    end

    redirect_to stats_path, notice: I18n.t('controllers.stats.stats_for_target_are_being_updated', target: target),
status: :see_other
  end

  def update_all
    Stats::EnqueueFullRecalculation.new(current_user).call

    redirect_to stats_path, notice: I18n.t('controllers.stats.stats_are_being_updated'), status: :see_other
  end

  private

  def validate_update_period!
    return if params[:month] == 'all' || params[:month].to_s.match?(/\A(?:0?[1-9]|1[0-2])\z/)

    redirect_to stats_path,
                alert: I18n.t('controllers.stats.invalid_period'),
                status: :see_other
  end

  def assign_points_statistics
    points_stats = ::StatsQuery.new(current_user).points_stats

    @points_total = points_stats[:total]
    @points_reverse_geocoded = points_stats[:geocoded]
    @points_reverse_geocoded_percentage = points_stats[:geocoded_percentage]
    @points_reverse_geocoded_without_data = points_stats[:without_data]
  end

  def precompute_year_distances
    year_distances = {}

    @stats.each do |year, stats|
      stats_by_month = stats.index_by(&:month)

      year_distances[year] = (1..12).map do |month|
        month_name = I18n.l(Date.new(year, month, 1), format: :month_name)
        distance = stats_by_month[month]&.distance || 0

        [month_name, distance]
      end
    end

    year_distances
  end

  def locked_years
    return [] unless current_user.plan_restricted?

    all_years = current_user.stats.distinct.pluck(:year)
    scoped_years = @stats.keys
    (all_years - scoped_years).sort.reverse
  end

  def build_stats
    columns = %i[id year month distance updated_at user_id]
    columns << :toponyms if Geocoding::Config.for(current_user).enabled?

    current_user.scoped_stats
                .select(columns)
                .order(year: :desc, updated_at: :desc)
                .group_by(&:year)
  end
end
