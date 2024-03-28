module ApplicationHelper
  def classes_for_flash(flash_type)
    case flash_type.to_sym
    when :error
      'bg-red-100 text-red-700 border-red-300'
    else
      'bg-blue-100 text-blue-700 border-blue-300'
    end
  end

  def month_timespan(stat)
    month = DateTime.new(stat.year, stat.month).in_time_zone(Time.zone)
    start_at = month.beginning_of_month.to_time.strftime('%Y-%m-%dT%H:%M')
    end_at = month.end_of_month.to_time.strftime('%Y-%m-%dT%H:%M')

    { start_at:, end_at: }
  end

  def year_timespan(year)
    start_at = DateTime.new(year).beginning_of_year.to_time.strftime('%Y-%m-%dT%H:%M')
    end_at = DateTime.new(year).end_of_year.to_time.strftime('%Y-%m-%dT%H:%M')

    { start_at: start_at, end_at: end_at }
  end

  def header_colors
    %w[info success warning error accent secondary primary]
  end

  def countries_and_cities_stat(year)
    data = Stat.year_cities_and_countries(year)
    countries = data[:countries]
    cities = data[:cities]

    "#{countries} countries, #{cities} cities"
  end

  def year_distance_stat_in_km(year)
    Stat.year_distance(year).sum { _1[1] }
  end
end
