# frozen_string_literal: true

module StatsComparisonHelper
  def x_than_average_distance(stat, average_distance_this_year)
    return '' if average_distance_this_year&.zero?

    current_km = stat.distance / 1000.0
    difference = current_km - average_distance_this_year.to_f
    percentage = ((difference / average_distance_this_year.to_f) * 100).round

    direction = difference.positive? ? 'more' : 'less'
    I18n.t("helpers.stats_comparison.distance.#{direction}", percentage: percentage.abs)
  end

  def x_than_previous_active_days(stat, previous_stat)
    return '' unless previous_stat

    previous_active_days = previous_stat.daily_distance.select { _1[1].positive? }.count
    current_active_days = stat.daily_distance.select { _1[1].positive? }.count
    difference = current_active_days - previous_active_days

    return I18n.t('helpers.stats_comparison.same_as_previous_month') if difference.zero?

    direction = difference.positive? ? 'more' : 'less'
    I18n.t("helpers.stats_comparison.active_days.#{direction}", count: difference.abs)
  end

  def x_than_previous_countries_visited(stat, previous_stat)
    return '' unless previous_stat

    previous_countries = previous_stat.toponyms.count { _1['country'] }
    current_countries = stat.toponyms.count { _1['country'] }
    difference = current_countries - previous_countries

    return I18n.t('helpers.stats_comparison.same_as_previous_month') if difference.zero?

    direction = difference.positive? ? 'more' : 'less'
    I18n.t("helpers.stats_comparison.countries.#{direction}", count: difference.abs)
  end
end
