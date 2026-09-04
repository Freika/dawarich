# frozen_string_literal: true

class Stats::CalculateMonth
  CALCULATION_VERSION = 2

  def initialize(user_id, year, month, notify_on_failure: true)
    @user = User.find(user_id)
    @year = year.to_i
    @month = month.to_i
    @notify_on_failure = notify_on_failure
  end

  def call
    if points.empty?
      reset_month_stats(year, month)

      return
    end

    update_month_stats(year, month)
  rescue StandardError => e
    report_failure(e)
  end

  private

  attr_reader :user, :year, :month, :notify_on_failure

  def start_timestamp = (DateTime.new(year, month, 1) - 2.days).to_i

  def end_timestamp
    (DateTime.new(year, month, -1).end_of_day + 2.days).to_i
  end

  def update_month_stats(year, month)
    Stat.transaction do
      stat = Stat.find_or_create_by!(year:, month:, user:) { |record| record.distance = 0 }
      # Serialize recalculation with geocoding invalidation for this month.
      # A geocoder finishing during this calculation must leave the month stale.
      stat.lock!
      distance_by_day = stat.distance_by_day

      stat.assign_attributes(
        daily_distance: distance_by_day,
        distance: distance(distance_by_day),
        flight_distance: flight_distance,
        toponyms: toponyms,
        h3_hex_ids: calculate_h3_hex_ids,
        calculation_version: CALCULATION_VERSION
      )

      stat.save!

      Cache::InvalidateUserCaches.new(user.id, year: year).call
    end
  end

  def points
    return @points if defined?(@points)

    @points = user
              .points
              .not_anomaly
              .where(timestamp: start_timestamp..end_timestamp)
              .select(:id, :lonlat, :timestamp, :city, :country_name, :country_id, :velocity)
              .order(timestamp: :asc)
  end

  def points_in_local_month
    tz = user.timezone_iana
    points.where(
      'EXTRACT(year FROM (to_timestamp(timestamp) AT TIME ZONE ?)) = ? ' \
      'AND EXTRACT(month FROM (to_timestamp(timestamp) AT TIME ZONE ?)) = ?',
      tz, year, tz, month
    )
  end

  def distance(distance_by_day)
    distance_by_day.sum { |day| day[1] }
  end

  def flight_distance
    Stats::FlightDistanceQuery.new(user, year, month).call
  end

  def toponyms
    CountriesAndCities.new(
      points_in_local_month,
      min_minutes_spent_in_city: user.safe_settings.min_minutes_spent_in_city
    ).call
  end

  def report_failure(error)
    message = "Stats::CalculateMonth failed for user #{user.id} #{year}-#{month}"

    Rails.logger.error("#{message}: #{error.class}: #{error.message}")
    ExceptionReporter.call(error, message)

    create_stats_update_failed_notification(user, error) if notify_on_failure
  end

  def create_stats_update_failed_notification(user, error)
    I18n.with_locale(user.locale) do
      Notifications::Create.new(
        user:,
        kind: :error,
        title: I18n.t('services.stats.calculate_month.stats_update_failed'),
        content: I18n.t('services.stats.calculate_month.message_stacktrace_n', message: error.message,
                        backtrace: error.backtrace.join("\n"))
      ).call
    end
  end

  def reset_month_stats(year, month)
    stat = Stat.find_by(year:, month:, user:)
    return unless stat

    stat.update!(
      daily_distance: {},
      distance: 0,
      flight_distance: flight_distance,
      toponyms: [],
      h3_hex_ids: {},
      calculation_version: CALCULATION_VERSION
    )

    Cache::InvalidateUserCaches.new(user.id, year: year).call
  end

  def calculate_h3_hex_ids
    Stats::HexagonCalculator.new(user.id, year, month).call
  end
end
