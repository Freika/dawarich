# frozen_string_literal: true

class InsightsController < ApplicationController
  before_action :authenticate_user!

  def index
    authorize :insights, :index?

    @available_years = current_user.stats.distinct.pluck(:year).sort.reverse
    @selected_year = params[:year] || @available_years.first&.to_s || Time.current.year.to_s
    @all_time = @selected_year == 'all'

    load_year_stats
    load_year_totals
    load_comparison_data if @previous_year_stats&.any?
    load_activity_heatmap

    if @all_time
      set_default_patterns
    else
      load_yearly_patterns
      load_monthly_digest
    end
  end

  private

  def load_year_stats
    if @all_time
      @year_stats = current_user.stats.order(year: :desc, month: :desc)
      @previous_year_stats = Stat.none
      @display_label = 'All Time'
    else
      @selected_year = @selected_year.to_i
      @previous_year = @selected_year - 1
      @year_stats = current_user.stats.where(year: @selected_year).order(:month)
      @previous_year_stats = current_user.stats.where(year: @previous_year).order(:month)
      @display_label = "#{@selected_year} Overview"
    end
  end

  def load_year_totals
    @year_totals = Insights::YearTotalsCalculator.new(@year_stats, distance_unit: distance_unit).call

    @total_distance = @year_totals.total_distance
    @countries_count = @year_totals.countries_count
    @cities_count = @year_totals.cities_count
    @countries_list = @year_totals.countries_list
    @days_traveling = @year_totals.days_traveling
    @biggest_month = @year_totals.biggest_month
  end

  def load_comparison_data
    comparison = Insights::YearComparisonCalculator.new(
      @year_totals,
      @previous_year_stats,
      distance_unit: distance_unit
    ).call

    @prev_total_distance = comparison.prev_total_distance
    @prev_countries_count = comparison.prev_countries_count
    @prev_cities_count = comparison.prev_cities_count
    @prev_days_traveling = comparison.prev_days_traveling
    @prev_biggest_month = comparison.prev_biggest_month
    @distance_change = comparison.distance_change
    @countries_change = comparison.countries_change
    @cities_change = comparison.cities_change
    @days_change = comparison.days_change
  end

  def load_activity_heatmap
    return if @all_time

    @activity_heatmap = Insights::ActivityHeatmapCalculator.new(@year_stats, @selected_year).call
  end

  def load_yearly_patterns
    yearly_digest = fetch_or_calculate_yearly_digest
    travel_patterns = yearly_digest&.travel_patterns || {}

    @time_of_day = travel_patterns['time_of_day'] || {}
    @day_of_week = calculate_yearly_day_of_week
    @seasonality = travel_patterns['seasonality'] || {}
    @activity_breakdown = travel_patterns['activity_breakdown'] || {}
    @top_visited_locations = fetch_yearly_top_visits
  end

  def fetch_or_calculate_yearly_digest
    cache_key = yearly_digest_cache_key

    Rails.cache.fetch(cache_key, expires_in: 1.hour) do
      digest = current_user.digests.yearly.find_by(year: @selected_year)

      if digest.nil? || digest_stale?(digest)
        digest = Users::Digests::CalculateYear.new(current_user.id, @selected_year).call
      end

      digest
    end
  end

  def yearly_digest_cache_key
    latest_stat = current_user.stats.where(year: @selected_year).maximum(:updated_at)
    latest_track = current_user.tracks
                               .where('start_at >= ? AND start_at <= ?',
                                      TimezoneHelper.year_start_time(@selected_year, current_user.timezone),
                                      TimezoneHelper.year_end_time(@selected_year, current_user.timezone))
                               .maximum(:updated_at)

    max_updated = [latest_stat, latest_track].compact.max.to_i
    "insights/yearly_digest/#{current_user.id}/#{@selected_year}/#{max_updated}"
  end

  def digest_stale?(digest)
    # Check if essential data is missing
    return true if digest.travel_patterns.blank?

    latest_stat_update = current_user.stats.where(year: @selected_year).maximum(:updated_at)
    return false if latest_stat_update.nil?

    digest.updated_at < latest_stat_update
  end

  def calculate_yearly_day_of_week
    monthly_digests = current_user.digests.monthly.where(year: @selected_year)
    weekly_totals = Array.new(7, 0)

    monthly_digests.each do |digest|
      pattern = digest.weekly_pattern
      next unless pattern.is_a?(Array) && pattern.size == 7

      pattern.each_with_index do |distance, idx|
        weekly_totals[idx] += distance.to_i
      end
    end

    weekly_totals
  end

  def fetch_yearly_top_visits
    start_time = TimezoneHelper.year_start_time(@selected_year, current_user.timezone)
    end_time = TimezoneHelper.year_end_time(@selected_year, current_user.timezone)

    current_user.visits.confirmed.where(started_at: start_time..end_time).group(:name)
                .select('name, COUNT(*) as visit_count, SUM(duration) as total_duration')
                .order('visit_count DESC, total_duration DESC').limit(5)
                .map { |v| { name: v.name, visit_count: v.visit_count, total_duration: v.total_duration } }
  end

  def load_monthly_digest
    @selected_month = determine_selected_month
    @available_months = current_user.stats
                                    .where(year: @selected_year)
                                    .pluck(:month)
                                    .sort

    @monthly_digest = current_user.digests
                                  .monthly
                                  .find_by(year: @selected_year, month: @selected_month)

    return unless @monthly_digest.nil? && @available_months.include?(@selected_month)

    @monthly_digest = Users::Digests::CalculateMonth
                      .new(current_user.id, @selected_year, @selected_month)
                      .call
  end

  def determine_selected_month
    if params[:month].present?
      params[:month].to_i
    elsif @selected_year == Time.current.year
      current_user.stats.where(year: @selected_year).maximum(:month) || Time.current.month
    else
      current_user.stats.where(year: @selected_year).maximum(:month) || 12
    end
  end

  def set_default_patterns
    @available_months = []
    @time_of_day = {}
    @day_of_week = Array.new(7, 0)
    @seasonality = {}
    @activity_breakdown = {}
    @top_visited_locations = []
  end

  def distance_unit
    current_user.safe_settings.distance_unit
  end
end
