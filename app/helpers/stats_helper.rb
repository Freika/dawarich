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
end
