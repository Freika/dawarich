# frozen_string_literal: true

class InsightsController < ApplicationController
  before_action :authenticate_user!

  def index
    @available_years = current_user.stats.distinct.pluck(:year).sort.reverse
    @selected_year = params[:year] || @available_years.first&.to_s || Time.current.year.to_s
    @all_time = @selected_year == 'all'

    load_year_stats
    load_year_totals
    load_comparison_data if @previous_year_stats&.any?

    if @all_time
      set_default_travel_patterns
    else
      load_monthly_data
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

  def load_monthly_data
    load_monthly_digest
    load_travel_patterns
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

  def load_travel_patterns
    patterns = Insights::TravelPatternsLoader.new(
      current_user,
      @selected_year,
      @selected_month,
      monthly_digest: @monthly_digest
    ).call

    @time_of_day = patterns.time_of_day
    @day_of_week = patterns.day_of_week
    @seasonality = patterns.seasonality
    @activity_breakdown = patterns.activity_breakdown
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

  def set_default_travel_patterns
    @available_months = []
    @time_of_day = {}
    @day_of_week = Array.new(7, 0)
    @seasonality = {}
    @activity_breakdown = {}
  end

  def distance_unit
    current_user.safe_settings.distance_unit
  end
end
