# frozen_string_literal: true

class StatsController < ApplicationController
  before_action :authenticate_user!
  before_action :authenticate_active_user!, only: %i[update update_all]

  def index
    @stats = current_user.stats.group_by(&:year).transform_values do |stats|
      stats.sort_by(&:updated_at).reverse
    end.sort.reverse

    # Single aggregated query to replace 3 separate COUNT queries
    result = current_user.tracked_points.connection.execute(<<~SQL.squish)
      SELECT#{' '}
        COUNT(*) as total,
        COUNT(reverse_geocoded_at) as geocoded,
        COUNT(CASE WHEN geodata = '{}' THEN 1 END) as without_data
      FROM points#{' '}
      WHERE user_id = #{current_user.id}
    SQL

    row = result.first
    @points_total = row['total'].to_i
    @points_reverse_geocoded = row['geocoded'].to_i
    @points_reverse_geocoded_without_data = row['without_data'].to_i

    # Precompute year distance data to avoid N+1 queries in view
    @year_distances = {}
    @stats.each do |year, _stats|
      @year_distances[year] = Stat.year_distance(year, current_user)
    end
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
