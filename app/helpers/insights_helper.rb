# frozen_string_literal: true

module InsightsHelper
  include CountryFlagHelper

  def monthly_digest_title(digest)
    return 'Monthly Digest' unless digest

    "#{digest.month_name} #{digest.year} Digest"
  end

  def monthly_digest_distance(digest, user)
    return '0' unless digest

    distance_unit = user.safe_settings.distance_unit
    value = Stat.convert_distance(digest.distance, distance_unit).round
    "#{number_with_delimiter(value)} #{distance_unit}"
  end

  def monthly_digest_active_days(digest)
    return '0/0' unless digest

    "#{digest.active_days_count}/#{digest.days_in_month}"
  end

  def previous_month_link(year, month, available_months)
    prev_date = Date.new(year, month, 1).prev_month

    # Check if previous month exists in available months (same year only for simplicity)
    return unless month > 1 && available_months.include?(prev_date.month)

    insights_path(year: prev_date.year, month: prev_date.month)
  end

  def next_month_link(year, month, available_months)
    next_date = Date.new(year, month, 1).next_month

    # Check if next month exists in available months (same year only for simplicity)
    return unless month < 12 && available_months.include?(next_date.month)

    insights_path(year: next_date.year, month: next_date.month)
  end

  def weekly_pattern_chart_data(digest, user)
    day_names = %w[Mon Tue Wed Thu Fri Sat Sun]
    return day_names.map { |day| [day, 0] } unless digest

    pattern = digest.weekly_pattern
    return day_names.map { |day| [day, 0] } unless pattern.is_a?(Array) && pattern.size == 7

    distance_unit = user.safe_settings.distance_unit
    day_names.each_with_index.map do |day, idx|
      distance_meters = pattern[idx] || 0
      converted = Stat.convert_distance(distance_meters, distance_unit).round
      [day, converted]
    end
  end

  def top_locations_from_digest(digest, limit = 3)
    return [] unless digest

    toponyms = digest.toponyms
    return [] unless toponyms.is_a?(Array)

    locations = []
    toponyms.each do |toponym|
      next unless toponym.is_a?(Hash)

      country = toponym['country']
      cities = toponym['cities']

      next unless cities.is_a?(Array) && cities.any?

      cities.each do |city|
        next unless city.is_a?(Hash)

        city_name = city['city']
        stayed_for = city['stayed_for'].to_i
        locations << {
          name: "#{city_name}, #{country_code(country)}",
          minutes: stayed_for
        }
      end
    end

    # Sort by minutes and take top N
    locations.sort_by { |l| -l[:minutes] }.first(limit)
  end

  def format_location_time(minutes)
    return '0 min' if minutes.nil? || minutes.to_i.zero?

    duration = ActiveSupport::Duration.build(minutes.to_i * 60)
    parts = duration.parts

    days = parts[:days] || 0
    hours = parts[:hours] || 0
    mins = parts[:minutes] || 0

    return "#{days} #{'day'.pluralize(days)}" if days >= 1
    return "#{hours} #{'hour'.pluralize(hours)}" if hours >= 1

    "#{mins} min"
  end

  def first_time_visits_from_digest(digest)
    return { countries: [], cities: [] } unless digest

    {
      countries: digest.first_time_countries || [],
      cities: digest.first_time_cities || []
    }
  end

  def generate_travel_insight(time_of_day, day_of_week, seasonality)
    Insights::TravelInsightGenerator.new(
      time_of_day: time_of_day,
      day_of_week: day_of_week,
      seasonality: seasonality
    ).call
  end

  # Format activity breakdown duration from seconds to human-readable hours
  def format_activity_hours(seconds)
    return '0h' if seconds.nil? || seconds.to_i.zero?

    hours = (seconds.to_i / 3600.0).round(1)
    if hours >= 1
      "#{hours.to_i == hours ? hours.to_i : hours}h"
    else
      minutes = (seconds.to_i / 60.0).round
      "#{minutes}min"
    end
  end

  # Calculate activity statistics from activity_breakdown hash
  # Returns: { walking: hours, cycling: hours, driving: hours, transport: hours, active: hours, stationary: hours }
  def activity_statistics(activity_breakdown)
    return empty_activity_stats if activity_breakdown.blank?

    stats = empty_activity_stats
    activity_breakdown.each { |mode, data| accumulate_activity_stat(stats, mode.to_s, data['duration'].to_i) }
    stats
  end

  def accumulate_activity_stat(stats, mode, duration)
    case mode
    when 'walking', 'running', 'cycling'
      stats[mode.to_sym] = duration
      stats[:active] += duration
    when 'stationary'
      stats[:stationary] = duration
    when 'driving', 'bus', 'train', 'flying', 'boat', 'motorcycle'
      stats[:driving] = duration if mode == 'driving'
      stats[:transport] += duration
    end
  end

  def empty_activity_stats
    { walking: 0, cycling: 0, running: 0, driving: 0, transport: 0, active: 0, stationary: 0 }
  end

  # Calculate activity ratio as "1:X" format (active vs sedentary)
  def activity_ratio(active_seconds, sedentary_seconds)
    return 'N/A' if active_seconds.to_i.zero? || sedentary_seconds.to_i.zero?

    ratio = sedentary_seconds.to_f / active_seconds
    "1:#{ratio.round}"
  end

  # Check if activity breakdown has meaningful data
  def activity_breakdown_present?(activity_breakdown)
    return false if activity_breakdown.blank?

    activity_breakdown.values.sum { |v| v['duration'].to_i }.positive?
  end

  # Activity heatmap helpers
  def calculate_activity_level(distance, levels)
    return 0 if distance.nil? || distance.to_i.zero?

    distance = distance.to_i
    return 4 if distance >= levels[:p90]
    return 3 if distance >= levels[:p75]
    return 2 if distance >= levels[:p50]
    return 1 if distance >= levels[:p25]

    1 # Any activity is at least level 1
  end

  def activity_level_class(level)
    case level
    when 0 then 'bg-base-300'
    when 1 then 'bg-success/30'
    when 2 then 'bg-success/50'
    when 3 then 'bg-success/70'
    when 4 then 'bg-success'
    else 'bg-base-300'
    end
  end

  def format_heatmap_distance(meters, unit)
    return '0' if meters.nil? || meters.to_i.zero?

    converted = Stat.convert_distance(meters.to_i, unit)
    if converted < 1
      if unit == 'mi'
        feet = (converted * 5280).round
        "#{feet} ft"
      else
        "#{meters.to_i} m"
      end
    else
      "#{converted.round(1)} #{unit}"
    end
  end

  def heatmap_week_columns(year)
    start_date = Date.new(year, 1, 1)
    end_date = Date.new(year, 12, 31)

    # Adjust to start from the Monday of the week containing Jan 1
    start_of_grid = start_date - (start_date.wday == 0 ? 6 : start_date.wday - 1)

    # Adjust to end at the Sunday of the week containing Dec 31
    end_of_grid = end_date + (end_date.wday == 0 ? 0 : 7 - end_date.wday)

    weeks = []
    current_week_start = start_of_grid

    while current_week_start <= end_of_grid
      weeks << current_week_start
      current_week_start += 7
    end

    weeks
  end

  def heatmap_month_labels(weeks, year)
    labels = []
    current_month = nil

    weeks.each_with_index do |week_start, index|
      # Get the date that falls within the target year for this week
      week_date = week_start
      7.times do |i|
        check_date = week_start + i
        if check_date.year == year
          week_date = check_date
          break
        end
      end

      next unless week_date.year == year

      if week_date.month != current_month
        current_month = week_date.month
        labels << { index: index, name: Date::ABBR_MONTHNAMES[current_month] }
      end
    end

    labels
  end

  private

  def country_code(country_name)
    country_to_code(country_name) || country_name&.first(2)&.upcase || '??'
  end
end
