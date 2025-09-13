# frozen_string_literal: true

module StatsHelper
  def year_distance_stat(year_data, user)
    total_distance_meters = year_data.sum { _1[1] }

    Stat.convert_distance(total_distance_meters, user.safe_settings.distance_unit)
  end

  def countries_and_cities_stat_for_year(year, stats)
    data = { countries: [], cities: [] }

    stats.select { _1.year == year }.each do
      data[:countries] << _1.toponyms.flatten.map { |t| t['country'] }.uniq.compact
      data[:cities] << _1.toponyms.flatten.flat_map { |t| t['cities'].map { |c| c['city'] } }.compact.uniq
    end

    data[:cities].flatten!.uniq!
    data[:countries].flatten!.uniq!

    grouped_by_country = {}
    stats.select { _1.year == year }.each do |stat|
      stat.toponyms.flatten.each do |toponym|
        country = toponym['country']
        next if country.blank?

        grouped_by_country[country] ||= []

        next if toponym['cities'].blank?

        toponym['cities'].each do |city_data|
          city = city_data['city']
          grouped_by_country[country] << city if city.present?
        end
      end
    end

    grouped_by_country.transform_values!(&:uniq)

    {
      countries_count: data[:countries].count,
      cities_count: data[:cities].count,
      grouped_by_country: grouped_by_country.transform_values(&:sort).sort.to_h,
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

  def active_days(stat)
    total_days = stat.daily_distance.count
    active_days = stat.daily_distance.select { _1[1].positive? }.count

    "#{active_days}/#{total_days}"
  end

  def countries_visited(stat)
    stat.toponyms.count { _1['country'] }
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

  def peak_day(stat)
    peak = stat.daily_distance.max_by { _1[1] }
    return 'N/A' unless peak && peak[1].positive?

    date = Date.new(stat.year, stat.month, peak[0])
    distance_unit = stat.user.safe_settings.distance_unit

    distance_value = Stat.convert_distance(peak[1], distance_unit).round
    text = "#{date.strftime('%B %d')} (#{distance_value} #{distance_unit})"

    link_to text, map_url(start_at: date.beginning_of_day, end_at: date.end_of_day), class: 'underline'
  end

  def quietest_week(stat)
    return 'N/A' if stat.daily_distance.empty?

    # Create a hash with date as key and distance as value
    distance_by_date = stat.daily_distance.to_h.transform_keys do |timestamp|
      Time.at(timestamp).in_time_zone(stat.user.timezone || 'UTC').to_date
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

  def month_color(stat)
    case stat.month
    when 1 then '#397bb5'
    when 2 then '#5A4E9D'
    when 3 then '#3B945E'
    when 4 then '#7BC96F'
    when 5 then '#FFD54F'
    when 6 then '#FFA94D'
    when 7 then '#FF6B6B'
    when 8 then '#FF8C42'
    when 9 then '#C97E4F'
    when 10 then '#8B4513'
    when 11 then '#5A2E2E'
    when 12 then '#265d7d'
    end
  end

  def month_gradient_classes(stat)
    case stat.month
    when 1 then 'bg-gradient-to-br from-blue-500 to-blue-800' # Winter blue
    when 2 then 'bg-gradient-to-bl from-blue-600 to-purple-600' # Purple
    when 3 then 'bg-gradient-to-tr from-green-400 to-green-700'     # Spring green
    when 4 then 'bg-gradient-to-tl from-green-500 to-green-700'     # Light green
    when 5 then 'bg-gradient-to-br from-yellow-400 to-yellow-600'   # Spring yellow
    when 6 then 'bg-gradient-to-bl from-orange-400 to-orange-600'   # Summer orange
    when 7 then 'bg-gradient-to-tr from-red-400 to-red-600'         # Summer red
    when 8 then 'bg-gradient-to-tl from-orange-600 to-red-400'      # Orange-red
    when 9 then 'bg-gradient-to-br from-orange-600 to-yellow-400'   # Autumn orange
    when 10 then 'bg-gradient-to-bl from-yellow-700 to-orange-700'  # Autumn brown
    when 11 then 'bg-gradient-to-tr from-red-800 to-red-900'        # Dark red
    when 12 then 'bg-gradient-to-tl from-blue-600 to-blue-700'      # Winter dark blue
    end
  end

  def month_bg_image(stat)
    case stat.month
    when 1 then image_url('backgrounds/months/anne-nygard-VwzfdVT6_9s-unsplash.jpg')
    when 2 then image_url('backgrounds/months/ainars-cekuls-buAAKQiMfoI-unsplash.jpg')
    when 3 then image_url('backgrounds/months/ahmad-hasan-xEYWelDHYF0-unsplash.jpg')
    when 4 then image_url('backgrounds/months/lily-Rg1nSqXNPN4-unsplash.jpg')
    when 5 then image_url('backgrounds/months/milan-de-clercq-YtllSzi2JLY-unsplash.jpg')
    when 6 then image_url('backgrounds/months/liana-mikah-6B05zlnPOEc-unsplash.jpg')
    when 7 then image_url('backgrounds/months/irina-iriser-fKAl8Oid6zM-unsplash.jpg')
    when 8 then image_url('backgrounds/months/nadiia-ploshchenko-ZnDtJaIec_E-unsplash.jpg')
    when 9 then image_url('backgrounds/months/gracehues-photography-AYtup7uqimA-unsplash.jpg')
    when 10 then image_url('backgrounds/months/babi-hdNa4GCCgbg-unsplash.jpg')
    when 11 then image_url('backgrounds/months/foto-phanatic-8LaUOtP-de4-unsplash.jpg')
    when 12 then image_url('backgrounds/months/henry-schneider-FqKPySIaxuE-unsplash.jpg')
    end
  end
end
