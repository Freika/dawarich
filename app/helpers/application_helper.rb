# frozen_string_literal: true

module ApplicationHelper
  def classes_for_flash(flash_type)
    case flash_type.to_sym
    when :error
      'bg-red-100 text-red-700 border-red-300'
    else
      'bg-blue-100 text-blue-700 border-blue-300'
    end
  end

  def year_timespan(year)
    start_at = DateTime.new(year).beginning_of_year.strftime('%Y-%m-%dT%H:%M')
    end_at = DateTime.new(year).end_of_year.strftime('%Y-%m-%dT%H:%M')

    { start_at:, end_at: }
  end

  def timespan(month, year)
    month = DateTime.new(year, month)
    start_at = month.beginning_of_month.to_time.strftime('%Y-%m-%dT%H:%M')
    end_at = month.end_of_month.to_time.strftime('%Y-%m-%dT%H:%M')

    { start_at:, end_at: }
  end

  def header_colors
    %w[info success warning error accent secondary primary]
  end

  def countries_and_cities_stat_for_year(year, stats)
    data = { countries: [], cities: [] }

    stats.select { _1.year == year }.each do
      data[:countries] << _1.toponyms.flatten.map { |t| t['country'] }.uniq.compact
      data[:cities] << _1.toponyms.flatten.flat_map { |t| t['cities'].map { |c| c['city'] } }.compact.uniq
    end

    data[:cities].flatten!.uniq!
    data[:countries].flatten!.uniq!

    # Group cities by country
    grouped_by_country = {}
    stats.select { _1.year == year }.each do |stat|
      stat.toponyms.flatten.each do |toponym|
        country = toponym['country']
        next unless country.present?

        grouped_by_country[country] ||= []

        if toponym['cities'].present?
          toponym['cities'].each do |city_data|
            city = city_data['city']
            grouped_by_country[country] << city if city.present?
          end
        end
      end
    end

    # Deduplicate cities for each country
    grouped_by_country.transform_values!(&:uniq)

    # Return data for the template to use
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

  def year_distance_stat(year, user)
    # In km or miles, depending on the user.safe_settings.distance_unit
    Stat.year_distance(year, user).sum { _1[1] }
  end

  def past?(year, month)
    DateTime.new(year, month).past?
  end

  def points_exist?(year, month, user)
    user.tracked_points.where(
      timestamp: DateTime.new(year, month).beginning_of_month..DateTime.new(year, month).end_of_month
    ).exists?
  end

  def new_version_available?
    CheckAppVersion.new.call
  end

  def app_theme
    current_user&.theme == 'light' ? 'light' : 'dark'
  end

  def sidebar_distance(distance)
    return unless distance

    "#{distance} #{current_user.safe_settings.distance_unit}"
  end

  def sidebar_points(points)
    return unless points

    points_number = points.size
    points_pluralized = pluralize(points_number, 'point')

    "(#{points_pluralized})"
  end

  def active_class?(link_path)
    'btn-active' if current_page?(link_path)
  end

  def full_title(page_title = '')
    base_title = 'Dawarich'
    page_title.empty? ? base_title : "#{page_title} | #{base_title}"
  end

  def active_tab?(link_path)
    'tab-active' if current_page?(link_path)
  end

  def active_visit_places_tab?(controller_name)
    'tab-active' if current_page?(controller: controller_name)
  end

  def notification_link_color(notification)
    return 'text-gray-600' if notification.read?

    'text-blue-600'
  end

  def human_date(date)
    date.strftime('%e %B %Y')
  end

  def human_datetime(datetime)
    return unless datetime

    content_tag(
      :span,
      datetime.strftime('%e %b %Y, %H:%M'),
      class: 'tooltip',
      data: { tip: datetime.iso8601 }
    )
  end

  def human_datetime_with_seconds(datetime)
    return unless datetime

    content_tag(
      :span,
      datetime.strftime('%e %b %Y, %H:%M:%S'),
      class: 'tooltip',
      data: { tip: datetime.iso8601 }
    )
  end

  def speed_text_color(speed)
    return 'text-default' if speed.to_i >= 0

    'text-red-500'
  end

  def point_speed(speed)
    return speed if speed.to_i <= 0

    speed * 3.6
  end

  def days_left(active_until)
    return unless active_until

    time_words = distance_of_time_in_words(Time.zone.now, active_until)

    content_tag(
      :span,
      time_words,
      class: 'tooltip',
      data: { tip: "Expires on #{active_until.iso8601}" }
    )
  end
end
