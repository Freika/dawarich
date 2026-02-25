# frozen_string_literal: true

module StatsComparisonHelper
  def x_than_average_distance(stat, average_distance_this_year)
    return '' if average_distance_this_year&.zero?

    current_km = stat.distance / 1000.0
    difference = current_km - average_distance_this_year.to_f
    percentage = ((difference / average_distance_this_year.to_f) * 100).round

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

  def x_than_previous_countries_visited(stat, previous_stat)
    return '' unless previous_stat

    previous_countries = previous_stat.toponyms.count { _1['country'] }
    current_countries = stat.toponyms.count { _1['country'] }
    difference = current_countries - previous_countries

    return 'Same as previous month' if difference.zero?

    more_or_less = difference.positive? ? 'more' : 'less'
    countries_word = pluralize(difference.abs, 'country')

    "#{countries_word} #{more_or_less} than previous month"
  end
end
