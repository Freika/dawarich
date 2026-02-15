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
    ).call

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
    ).call

    expires_in 5.minutes, public: false
    render json: result
  end

  private

  def load_year_data
    @available_years = current_api_user.stats.distinct.pluck(:year).sort.reverse
    @selected_year = (params[:year] || @available_years.first || Time.current.year).to_i
    @year_stats = current_api_user.stats.where(year: @selected_year).order(:month)
  end

  def load_totals
    @totals = Insights::YearTotalsCalculator.new(@year_stats, distance_unit: distance_unit).call
  end

  def load_heatmap
    @heatmap = Insights::ActivityHeatmapCalculator.new(@year_stats, @selected_year).call
  end

  def load_comparison
    previous_year_stats = current_api_user.stats.where(year: @selected_year - 1).order(:month)
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
      day_of_week: calculate_yearly_day_of_week,
      seasonality: patterns['seasonality'] || {},
      activity_breakdown: patterns['activity_breakdown'] || {},
      top_visited_locations: fetch_yearly_top_visits
    }
  end

  def calculate_yearly_day_of_week
    digests = current_api_user.digests.monthly
                              .where(year: @selected_year)
                              .select(:id, :year, :month, :daily_distances)

    digests.each_with_object(Array.new(7, 0)) do |digest, weekly_totals|
      pattern = digest.weekly_pattern
      next unless pattern.is_a?(Array) && pattern.size == 7

      pattern.each_with_index do |distance, idx|
        weekly_totals[idx] += distance.to_i
      end
    end
  end

  def fetch_yearly_top_visits
    start_time = Time.zone.local(@selected_year, 1, 1)
    end_time = Time.zone.local(@selected_year, 12, 31).end_of_year

    current_api_user.visits.confirmed.where(started_at: start_time..end_time).group(:name)
                    .select('name, COUNT(*) as visit_count, SUM(duration) as total_duration')
                    .order('visit_count DESC, total_duration DESC').limit(5)
                    .map { |v| { name: v.name, visitCount: v.visit_count, totalDuration: v.total_duration } }
  end

  def distance_unit
    params[:distance_unit].presence || current_api_user.safe_settings.distance_unit || 'km'
  end
end
