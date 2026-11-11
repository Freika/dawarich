# frozen_string_literal: true

class Api::V1::InsightsController < ApiController
  def index
    load_year_data
    load_totals
    load_heatmap

    result = Api::InsightsOverviewSerializer.new(
      year: @selected_year,
      available_years: @available_years,
      totals: @totals,
      heatmap: @heatmap,
      distance_unit: distance_unit
    ).call.merge(plan_metadata)

    expires_in 5.minutes, public: false
    render json: result
  end

  def details
    load_year_data
    load_totals
    load_comparison
    load_travel_patterns

    result = Api::InsightsDetailsSerializer.new(
      year: @selected_year,
      comparison: @comparison,
      travel_patterns: @travel_patterns
    ).call.merge(plan_metadata)

    expires_in 5.minutes, public: false
    render json: result
  end

  private

  def load_year_data
    @available_years = current_api_user.scoped_stats.distinct.pluck(:year).sort.reverse
    @selected_year = (params[:year] || @available_years.first || Time.current.year).to_i
    @year_stats = current_api_user.scoped_stats.where(year: @selected_year).order(:month)
  end

  def load_totals
    @totals = Insights::YearTotalsCalculator.new(@year_stats, distance_unit: distance_unit).call
  end

  def load_heatmap
    @heatmap = Insights::ActivityHeatmapCalculator.new(@year_stats, @selected_year).call
  end

  def load_comparison
    previous_year_stats = current_api_user.scoped_stats.where(year: @selected_year - 1).order(:month)
    @comparison = if previous_year_stats.any?
                    Insights::YearComparisonCalculator.new(
                      @totals, previous_year_stats, distance_unit: distance_unit
                    ).call
                  end
  end

  def load_travel_patterns
    yearly_digest = current_api_user.digests.yearly.find_by(year: @selected_year)
    patterns = yearly_digest&.travel_patterns || {}

    @travel_patterns = {
      time_of_day: patterns['time_of_day'] || {},
      day_of_week: Insights::WeeklyDistanceTotals.new(current_api_user, @selected_year).call,
      seasonality: patterns['seasonality'] || {},
      activity_breakdown: patterns['activity_breakdown'] || {},
      top_visited_locations: fetch_yearly_top_visits
    }
  end

  def fetch_yearly_top_visits
    Insights::TopVisitedLocations.new(current_api_user, @selected_year).call.map do |location|
      { name: location[:name], visitCount: location[:visit_count], totalDuration: location[:total_duration] }
    end
  end

  def plan_metadata
    {
      planRestricted: current_api_user.plan_restricted?,
      upgradeUrl: upgrade_url_for(current_api_user)
    }
  end
end
