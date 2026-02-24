# frozen_string_literal: true

module StatsHelper
  def year_distance_stat(year_data, user)
    Stat.convert_distance(year_data.sum { _1[1] }, user.safe_settings.distance_unit)
  end

  def countries_and_cities_stat_for_year(year, stats)
    year_stats = stats.select { _1.year == year }
    countries, cities = collect_countries_and_cities(year_stats)
    grouped = group_toponyms_by_country(year_stats)

    {
      countries_count: countries.count,
      cities_count: cities.count,
      grouped_by_country: grouped.transform_values(&:sort).sort.to_h,
      year: year,
      modal_id: "countries_cities_modal_#{year}"
    }
  end

  def countries_and_cities_stat_for_month(stat)
    countries = stat.toponyms.count { _1['country'] }
    cities = stat.toponyms.sum { _1['cities'].count }

    "#{countries} countries, #{cities} cities"
  end

  def distance_traveled(user, stat)
    distance_unit = user.safe_settings.distance_unit
    value = Stat.convert_distance(stat.distance, distance_unit).round

    "#{number_with_delimiter(value)} #{distance_unit}"
  end

  def active_days(stat)
    total_days = stat.daily_distance.count
    active_days = stat.daily_distance.select { _1[1].positive? }.count

    "#{active_days}/#{total_days}"
  end

  def countries_visited(stat)
    stat.toponyms.count { _1['country'] }
  end

  def peak_day(stat)
    peak = stat.daily_distance.max_by { _1[1] }
    return 'N/A' unless peak && peak[1].positive?

    date = Date.new(stat.year, stat.month, peak[0])
    distance_unit = stat.user.safe_settings.distance_unit

    distance_value = Stat.convert_distance(peak[1], distance_unit).round
    text = "#{date.strftime('%B %d')} (#{distance_value} #{distance_unit})"

    link_to text, preferred_map_path(start_at: date.beginning_of_day, end_at: date.end_of_day), class: 'underline'
  end

  def quietest_week(stat)
    return 'N/A' if stat.daily_distance.empty?

    distance_by_date = build_distance_by_date_hash(stat)
    quietest_start_date = find_quietest_week_start_date(stat, distance_by_date)

    return 'N/A' unless quietest_start_date

    format_week_range(quietest_start_date)
  end

  private

  def collect_countries_and_cities(year_stats)
    countries = []
    cities = []

    year_stats.each do |stat|
      toponyms = stat.toponyms.flatten
      countries.concat(toponyms.map { |t| t['country'] }.compact)
      cities.concat(toponyms.flat_map { |t| (t['cities'] || []).map { |c| c['city'] } }.compact)
    end

    [countries.uniq, cities.uniq]
  end

  def group_toponyms_by_country(year_stats)
    grouped = Hash.new { |h, k| h[k] = [] }

    year_stats.each do |stat|
      stat.toponyms.flatten.each do |toponym|
        country = toponym['country']
        next if country.blank?

        (toponym['cities'] || []).each do |city_data|
          city = city_data['city']
          grouped[country] << city if city.present?
        end
      end
    end

    grouped.transform_values!(&:uniq)
  end

  def build_distance_by_date_hash(stat)
    stat.daily_distance.to_h.transform_keys do |day_number|
      Date.new(stat.year, stat.month, day_number)
    end
  end

  def find_quietest_week_start_date(stat, distance_by_date)
    quietest_start_date = nil
    quietest_distance = Float::INFINITY
    stat_month_start = Date.new(stat.year, stat.month, 1)
    stat_month_end = stat_month_start.end_of_month

    (stat_month_start..(stat_month_end - 6.days)).each do |start_date|
      week_dates = (start_date..(start_date + 6.days)).to_a
      week_distance = week_dates.sum { |date| distance_by_date[date] || 0 }

      if week_distance < quietest_distance
        quietest_distance = week_distance
        quietest_start_date = start_date
      end
    end

    quietest_start_date
  end

  def format_week_range(start_date)
    end_date = start_date + 6.days
    start_str = start_date.strftime('%b %d')
    end_str = end_date.strftime('%b %d')
    "#{start_str} - #{end_str}"
  end
end
