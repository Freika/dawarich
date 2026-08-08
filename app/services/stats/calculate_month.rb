# frozen_string_literal: true

class Stats::CalculateMonth
  def initialize(user_id, year, month)
    @user = User.find(user_id)
    @year = year.to_i
    @month = month.to_i
  end

  def call
    if points.empty?
      reset_month_stats(year, month)

      return
    end

    update_month_stats(year, month)
  rescue StandardError => e
    create_stats_update_failed_notification(user, e)
  end

  private

  attr_reader :user, :year, :month

  def start_timestamp = (DateTime.new(year, month, 1) - 2.days).to_i

  def end_timestamp
    (DateTime.new(year, month, -1).end_of_day + 2.days).to_i
  end

  def update_month_stats(year, month)
    Stat.transaction do
      stat = Stat.find_or_initialize_by(year:, month:, user:)
      distance_by_day = stat.distance_by_day

      stat.assign_attributes(
        daily_distance: distance_by_day,
        distance: distance(distance_by_day),
        toponyms: toponyms,
        h3_hex_ids: calculate_h3_hex_ids
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
              .without_raw_data
              .where(timestamp: start_timestamp..end_timestamp)
              .select(:lonlat, :timestamp, :city, :country_name, :country_id, :velocity)
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

  def toponyms
    CountriesAndCities.new(
      points_in_local_month,
      min_minutes_spent_in_city: user.safe_settings.min_minutes_spent_in_city,
      max_gap_minutes: user.safe_settings.max_gap_minutes_in_city
    ).call
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
      toponyms: [],
      h3_hex_ids: {}
    )

    Cache::InvalidateUserCaches.new(user.id, year: year).call
  end

  def calculate_h3_hex_ids
    Stats::HexagonCalculator.new(user.id, year, month).call
  end
end
