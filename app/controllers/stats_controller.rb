# frozen_string_literal: true

class StatsController < ApplicationController
  before_action :authenticate_user!, except: [:public_show]
  before_action :authenticate_active_user!, only: %i[update update_all update_sharing]

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
    @average_distance_this_year = current_user.stats.where(year: @year).average(:distance) / 1000
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

  def update_sharing
    @year = params[:year].to_i
    @month = params[:month].to_i
    @stat = current_user.stats.find_by(year: @year, month: @month)

    return head :not_found unless @stat

    if params[:enabled] == '1'
      @stat.enable_sharing!(expiration: params[:expiration] || 'permanent')
      sharing_url = public_stat_url(@stat.sharing_uuid)

      render json: {
        success: true,
        sharing_url: sharing_url,
        message: 'Sharing enabled successfully'
      }
    else
      @stat.disable_sharing!

      render json: {
        success: true,
        message: 'Sharing disabled successfully'
      }
    end
  rescue StandardError
    render json: {
      success: false,
      message: 'Failed to update sharing settings'
    }, status: :unprocessable_entity
  end

  def public_show
    @stat = Stat.find_by(sharing_uuid: params[:uuid])

    unless @stat&.public_accessible?
      return redirect_to root_path,
                         alert: 'Shared stats not found or no longer available'
    end

    @year = @stat.year
    @month = @stat.month
    @user = @stat.user
    @is_public_view = true
    @data_bounds = calculate_data_bounds(@stat)

    render 'public_month'
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

  def calculate_data_bounds(stat)
    start_date = Date.new(stat.year, stat.month, 1).beginning_of_day
    end_date = start_date.end_of_month.end_of_day
    
    points_relation = stat.user.points.where(timestamp: start_date.to_i..end_date.to_i)
    point_count = points_relation.count
    
    return nil if point_count.zero?

    bounds_result = ActiveRecord::Base.connection.exec_query(
      "SELECT MIN(latitude) as min_lat, MAX(latitude) as max_lat,
              MIN(longitude) as min_lng, MAX(longitude) as max_lng
       FROM points
       WHERE user_id = $1
       AND timestamp BETWEEN $2 AND $3",
      'data_bounds_query',
      [stat.user.id, start_date.to_i, end_date.to_i]
    ).first

    {
      min_lat: bounds_result['min_lat'].to_f,
      max_lat: bounds_result['max_lat'].to_f,
      min_lng: bounds_result['min_lng'].to_f,
      max_lng: bounds_result['max_lng'].to_f,
      point_count: point_count
    }
  end
end
