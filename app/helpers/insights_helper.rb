# frozen_string_literal: true

module InsightsHelper
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
    prev_month = month - 1
    prev_year = year

    if prev_month.zero?
      prev_month = 12
      prev_year = year - 1
    end

    # Check if previous month exists in available months (same year only for simplicity)
    # or if we're crossing years, we'd need to check previous year's data
    return unless month > 1 && available_months.include?(prev_month)

    insights_path(year: prev_year, month: prev_month)
  end

  def next_month_link(year, month, available_months)
    next_month = month + 1
    next_year = year

    if next_month > 12
      next_month = 1
      next_year = year + 1
    end

    # Check if next month exists in available months
    return unless month < 12 && available_months.include?(next_month)

    insights_path(year: next_year, month: next_month)
  end

  def weekly_pattern_heights(digest)
    return Array.new(7, 0) unless digest

    pattern = digest.weekly_pattern
    return Array.new(7, 0) unless pattern.is_a?(Array) && pattern.any?

    max_value = pattern.max.to_f
    return Array.new(7, 0) if max_value.zero?

    pattern.map { |v| ((v.to_f / max_value) * 100).round }
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
    days = minutes / 1440
    return "#{days} days" if days >= 1

    hours = minutes / 60
    return "#{hours} hours" if hours >= 1

    "#{minutes} min"
  end

  def first_time_visits_from_digest(digest)
    return { countries: [], cities: [] } unless digest

    {
      countries: digest.first_time_countries || [],
      cities: digest.first_time_cities || []
    }
  end

  private

  def country_code(country_name)
    # Simple country name to code mapping for common countries
    codes = {
      'Germany' => 'DE', 'France' => 'FR', 'Italy' => 'IT', 'Spain' => 'ES',
      'United Kingdom' => 'UK', 'Netherlands' => 'NL', 'Belgium' => 'BE',
      'Austria' => 'AT', 'Switzerland' => 'CH', 'Poland' => 'PL',
      'Czech Republic' => 'CZ', 'Sweden' => 'SE', 'Denmark' => 'DK',
      'Norway' => 'NO', 'Finland' => 'FI', 'Portugal' => 'PT',
      'United States' => 'US', 'Canada' => 'CA', 'Japan' => 'JP',
      'Australia' => 'AU', 'New Zealand' => 'NZ'
    }
    codes[country_name] || country_name&.first(2)&.upcase || '??'
  end
end
