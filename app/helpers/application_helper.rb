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

    "#{data[:countries].count} countries, #{data[:cities].count} cities"
  end

  def countries_and_cities_stat_for_month(stat)
    countries = stat.toponyms.count { _1['country'] }
    cities = stat.toponyms.sum { _1['cities'].count }

    "#{countries} countries, #{cities} cities"
  end

  def year_distance_stat(year, user)
    # In km or miles, depending on the application settings (DISTANCE_UNIT)
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

    "#{distance} #{DISTANCE_UNIT}"
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

  def notification_link_color(notification)
    return 'text-gray-600' if notification.read?

    'text-blue-600'
  end

  def human_date(date)
    date.strftime('%e %B %Y')
  end
end
