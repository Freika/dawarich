# frozen_string_literal: true

class Stats::CalculateMonth
  def initialize(user_id, year, month)
    @user = User.find(user_id)
    @year = year.to_i
    @month = month.to_i
  end

  def call
    if points.empty?
      destroy_month_stats(year, month)

      return
    end

    update_month_stats(year, month)
  rescue StandardError => e
    create_stats_update_failed_notification(user, e)
  end

  private

  attr_reader :user, :year, :month

  def start_timestamp = DateTime.new(year, month, 1).to_i

  def end_timestamp
    DateTime.new(year, month, -1).to_i # -1 returns last day of month
  end

  def update_month_stats(year, month)
    Stat.transaction do
      stat = Stat.find_or_initialize_by(year:, month:, user:)
      distance_by_day = stat.distance_by_day

      stat.assign_attributes(
        daily_distance: distance_by_day,
        distance: distance(distance_by_day),
        toponyms: toponyms
      )
      stat.save
    end
  end

  def points
    return @points if defined?(@points)

    @points = user
              .tracked_points
              .without_raw_data
              .where(timestamp: start_timestamp..end_timestamp)
              .select(:lonlat, :timestamp)
              .order(timestamp: :asc)
  end

  def distance(distance_by_day)
    distance_by_day.sum { |day| day[1] }
  end

  def toponyms
    toponym_points = user
                      .tracked_points
                      .without_raw_data
                      .where(timestamp: start_timestamp..end_timestamp)
                      .select(:city, :country_name)
                      .distinct

    CountriesAndCities.new(toponym_points).call
  end

  def create_stats_update_failed_notification(user, error)
    Notifications::Create.new(
      user:,
      kind: :error,
      title: 'Stats update failed',
      content: "#{error.message}, stacktrace: #{error.backtrace.join("\n")}"
    ).call
  end

  def destroy_month_stats(year, month)
    Stat.where(year:, month:, user:).destroy_all
  end
end
