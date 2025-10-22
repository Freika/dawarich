# frozen_string_literal: true

class Digests::Calculator
  def initialize(user, period:, year:, month: nil)
    @user = user
    @period = period  # :monthly or :yearly
    @year = year
    @month = month
    @date_range = build_date_range
  end

  def call
    {
      period_type: @period,
      year: @year,
      month: @month,
      period_label: period_label,
      overview: overview_data,
      distance_stats: distance_stats,
      top_cities: top_cities,
      visited_places: visited_places,
      trips: trips_data,
      all_time_stats: all_time_stats
    }
  rescue StandardError => e
    Rails.logger.error("Digest calculation failed: #{e.message}")
    Rails.logger.error(e.backtrace.join("\n"))
    nil
  end

  private

  def build_date_range
    case @period
    when :monthly
      start_date = Date.new(@year, @month, 1).beginning_of_day
      end_date = start_date.end_of_month.end_of_day
      start_date..end_date
    when :yearly
      start_date = Date.new(@year, 1, 1).beginning_of_day
      end_date = start_date.end_of_year.end_of_day
      start_date..end_date
    end
  end

  def period_label
    case @period
    when :monthly
      "#{Date::MONTHNAMES[@month]} #{@year}"
    when :yearly
      "#{@year}"
    end
  end

  def overview_data
    Digests::Queries::Overview.new(@user, @date_range).call
  end

  def distance_stats
    Digests::Queries::Distance.new(@user, @date_range).call
  end

  def top_cities
    Digests::Queries::Cities.new(@user, @date_range).call
  end

  def visited_places
    Digests::Queries::Places.new(@user, @date_range).call
  end

  def trips_data
    Digests::Queries::Trips.new(@user, @date_range).call
  end

  def all_time_stats
    Digests::Queries::AllTime.new(@user).call
  end
end
