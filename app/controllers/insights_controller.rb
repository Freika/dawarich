# frozen_string_literal: true

class InsightsController < ApplicationController
  before_action :authenticate_user!

  def index
    @available_years = current_user.stats.distinct.pluck(:year).sort.reverse
    @selected_year = params[:year] || @available_years.first&.to_s || Time.current.year.to_s
    @all_time = @selected_year == 'all'

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

    calculate_year_totals
    calculate_comparison_data if @previous_year_stats.any?
    load_monthly_digest unless @all_time
    load_travel_patterns unless @all_time
  end

  private

  def load_monthly_digest
    @selected_month = determine_selected_month
    @available_months = current_user.stats
                                    .where(year: @selected_year)
                                    .pluck(:month)
                                    .sort

    @monthly_digest = current_user.digests
                                  .monthly
                                  .find_by(year: @selected_year, month: @selected_month)

    # Calculate on-demand if not exists
    return unless @monthly_digest.nil? && @available_months.include?(@selected_month)

    @monthly_digest = Users::Digests::CalculateMonth
                      .new(current_user.id, @selected_year, @selected_month)
                      .call
  end

  def load_travel_patterns
    # Time of day from monthly digest (or calculate on-demand)
    @time_of_day = @monthly_digest&.time_of_day_distribution.presence ||
                   Stats::TimeOfDayQuery.new(current_user, @selected_year, @selected_month, user_timezone).call

    # Day of week from monthly digest
    @day_of_week = @monthly_digest&.weekly_pattern.presence || Array.new(7, 0)

    # Seasonality from yearly digest (or calculate on-demand)
    yearly_digest = current_user.digests.yearly.find_by(year: @selected_year)
    @seasonality = yearly_digest&.seasonality.presence ||
                   Users::Digests::SeasonalityCalculator.new(current_user, @selected_year).call
  end

  def user_timezone
    current_user.timezone
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

  def calculate_year_totals
    # Total distance for the year
    total_distance_meters = @year_stats.sum(:distance)
    @total_distance = Stat.convert_distance(total_distance_meters, distance_unit).round

    # Countries and cities from toponyms
    countries = Set.new
    cities = Set.new

    @year_stats.each do |stat|
      next unless stat.toponyms.is_a?(Array)

      stat.toponyms.each do |toponym|
        next unless toponym.is_a?(Hash)

        countries.add(toponym['country']) if toponym['country'].present?

        next unless toponym['cities'].is_a?(Array)

        toponym['cities'].each do |city|
          cities.add(city['city']) if city.is_a?(Hash) && city['city'].present?
        end
      end
    end

    @countries_count = countries.size
    @cities_count = cities.size
    @countries_list = countries.to_a.sort

    # Days traveling (active days with distance > 0)
    @days_traveling = @year_stats.sum do |stat|
      stat.daily_distance.count { |_day, distance| distance.to_i.positive? }
    end

    # Biggest month
    @biggest_month = find_biggest_month(@year_stats)
  end

  def find_biggest_month(stats)
    return nil if stats.empty?

    max_stat = stats.max_by(&:distance)
    return nil unless max_stat&.distance&.positive?

    {
      month: Date::MONTHNAMES[max_stat.month],
      distance: Stat.convert_distance(max_stat.distance, distance_unit).round
    }
  end

  def calculate_comparison_data
    # Previous year totals
    prev_distance_meters = @previous_year_stats.sum(:distance)
    @prev_total_distance = Stat.convert_distance(prev_distance_meters, distance_unit).round

    # Previous year countries and cities
    prev_countries = Set.new
    prev_cities = Set.new

    @previous_year_stats.each do |stat|
      next unless stat.toponyms.is_a?(Array)

      stat.toponyms.each do |toponym|
        next unless toponym.is_a?(Hash)

        prev_countries.add(toponym['country']) if toponym['country'].present?

        next unless toponym['cities'].is_a?(Array)

        toponym['cities'].each do |city|
          prev_cities.add(city['city']) if city.is_a?(Hash) && city['city'].present?
        end
      end
    end

    @prev_countries_count = prev_countries.size
    @prev_cities_count = prev_cities.size

    # Previous year days traveling
    @prev_days_traveling = @previous_year_stats.sum do |stat|
      stat.daily_distance.count { |_day, distance| distance.to_i.positive? }
    end

    # Previous year biggest month
    @prev_biggest_month = find_biggest_month(@previous_year_stats)

    # Calculate percentage changes
    @distance_change = calculate_change(@total_distance, @prev_total_distance)
    @countries_change = @countries_count - @prev_countries_count
    @cities_change = calculate_change(@cities_count, @prev_cities_count)
    @days_change = calculate_change(@days_traveling, @prev_days_traveling)
  end

  def calculate_change(current, previous)
    return 0 if previous.zero?

    ((current - previous).to_f / previous * 100).round
  end

  def distance_unit
    current_user.safe_settings.distance_unit
  end
end
