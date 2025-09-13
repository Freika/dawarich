# frozen_string_literal: true

class HexagonCacheService
  def initialize(user:, stat: nil, start_date: nil, end_date: nil)
    @user = user
    @stat = stat
    @start_date = start_date
    @end_date = end_date
  end

  def available?(hex_size)
    return false unless @user
    return false unless hex_size.to_i == 1000

    target_stat&.hexagons_available?(hex_size)
  end

  def cached_geojson(hex_size)
    return nil unless target_stat

    target_stat.hexagon_data.dig(hex_size.to_s, 'geojson')
  rescue StandardError => e
    Rails.logger.warn "Failed to retrieve cached hexagon data: #{e.message}"
    nil
  end

  private

  attr_reader :user, :stat, :start_date, :end_date

  def target_stat
    @target_stat ||= stat || find_monthly_stat
  end

  def find_monthly_stat
    return nil unless start_date && end_date

    begin
      start_time = Time.zone.parse(start_date)
      end_time = Time.zone.parse(end_date)

      # Only use cached data for exact monthly requests
      return nil unless monthly_date_range?(start_time, end_time)

      user.stats.find_by(year: start_time.year, month: start_time.month)
    rescue StandardError
      nil
    end
  end

  def monthly_date_range?(start_time, end_time)
    start_time.beginning_of_month == start_time &&
      end_time.end_of_month.beginning_of_day.to_date == end_time.to_date &&
      start_time.month == end_time.month &&
      start_time.year == end_time.year
  end
end
