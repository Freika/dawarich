# frozen_string_literal: true

module StatsHelper
  def distance_traveled(user, stat)
    distance_unit = user.safe_settings.distance_unit

    value =
      if distance_unit == 'mi'
        (stat.distance / 1609.34).round(2)
      else
        (stat.distance / 1000).round(2)
      end

    "#{number_with_delimiter(value)} #{distance_unit}"
  end

  def x_than_average_distance(stat, average_distance_this_year)
    return '' if average_distance_this_year.zero?

    difference = stat.distance / 1000 - average_distance_this_year
    percentage = ((difference / average_distance_this_year) * 100).round

    more_or_less = difference.positive? ? 'more' : 'less'
    "#{percentage.abs}% #{more_or_less} than your average this year"
  end

  def x_than_previous_active_days(stat, previous_stat)
    return '' unless previous_stat

    previous_active_days = previous_stat.daily_distance.select { _1[1].positive? }.count
    current_active_days = stat.daily_distance.select { _1[1].positive? }.count
    difference = current_active_days - previous_active_days

    return 'Same as previous month' if difference.zero?

    more_or_less = difference.positive? ? 'more' : 'less'
    days_word = pluralize(difference.abs, 'day')

    "#{days_word} #{more_or_less} than previous month"
  end

  def active_days(stat)
    total_days = stat.daily_distance.count
    active_days = stat.daily_distance.select { _1[1].positive? }.count

    "#{active_days}/#{total_days}"
  end

  def countries_visited(stat)
    stat.toponyms.count { _1['country'] }
  end

  def x_than_prevopis_countries_visited(stat, previous_stat)
    return '' unless previous_stat

    previous_countries = previous_stat.toponyms.count { _1['country'] }
    current_countries = stat.toponyms.count { _1['country'] }
    difference = current_countries - previous_countries

    return 'Same as previous month' if difference.zero?

    more_or_less = difference.positive? ? 'more' : 'less'
    countries_word = pluralize(difference.abs, 'country')

    "#{countries_word} #{more_or_less} than previous month"
  end

  def peak_day(stat)
    peak = stat.daily_distance.max_by { _1[1] }
    return 'N/A' unless peak && peak[1].positive?

    date = Date.new(stat.year, stat.month, peak[0])
    distance_km = (peak[1] / 1000).round(2)
    distance_unit = current_user.safe_settings.distance_unit

    distance_value =
      if distance_unit == 'mi'
        (peak[1] / 1609.34).round(2)
      else
        distance_km
      end

    text = "#{date.strftime('%B %d')} (#{distance_value} #{distance_unit})"

    link_to text, map_url(start_at: date.beginning_of_day, end_at: date.end_of_day), class: 'underline'
  end

  def quietest_week(stat)
    return 'N/A' if stat.daily_distance.empty?

    # Create a hash with date as key and distance as value
    distance_by_date = stat.daily_distance.to_h.transform_keys do |timestamp|
      Time.at(timestamp).in_time_zone(current_user.timezone || 'UTC').to_date
    end

    # Initialize variables to track the quietest week
    quietest_start_date = nil
    quietest_distance = Float::INFINITY

    # Iterate through each day of the month to find the quietest week
    start_date = distance_by_date.keys.min.beginning_of_month
    end_date = distance_by_date.keys.max.end_of_month

    (start_date..end_date).each_cons(7) do |week|
      week_distance = week.sum { |date| distance_by_date[date] || 0 }

      if week_distance < quietest_distance
        quietest_distance = week_distance
        quietest_start_date = week.first
      end
    end

    return 'N/A' unless quietest_start_date

    quietest_end_date = quietest_start_date + 6.days
    start_str = quietest_start_date.strftime('%b %d')
    end_str = quietest_end_date.strftime('%b %d')

    "#{start_str} - #{end_str}"
  end

  def month_icon(stat)
    case stat.month
    when 1..2, 12 then 'snowflake'
    when 3..5 then 'flower'
    when 6..8 then 'tree-palm'
    when 9..11 then 'leaf'
    end
  end
end
