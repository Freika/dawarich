# frozen_string_literal: true

class Stats::Calculate
  def initialize(user_id, start_at: nil, end_at: nil)
    @user = User.find(user_id)
    @start_at = start_at || DateTime.new(1970, 1, 1)
    @end_at = end_at || Time.current
  end

  def call
    # 1. Get all points for given user and time period
    points = points(start_timestamp, end_timestamp)

    # 2. Split points by months
    points_by_month = points.group_by_month(&:recorded_at)

    # 3. Calculate stats for each month
    points_by_month.each do |month, month_points|
      update_month_stats(month_points, month.year, month.month)
    end
    # 4. Save stats
  rescue StandardError => e
    create_stats_update_failed_notification(user, e)
  end

  private

  attr_reader :user, :start_at, :end_at

  def start_timestamp = start_at.to_i
  def end_timestamp   = end_at.to_i

  def update_month_stats(month_points, year, month)
    return if month_points.empty?

    stat = current_stat(year, month)
    distance_by_day = stat.distance_by_day

    stat.daily_distance = distance_by_day
    stat.distance = distance(distance_by_day)
    stat.toponyms = toponyms(month_points)
    stat.save
  end

  def points(start_at, end_at)
    user
      .tracked_points
      .without_raw_data
      .where(timestamp: start_at..end_at)
      .order(:timestamp)
      .select(:latitude, :longitude, :timestamp, :city, :country)
  end

  def distance(distance_by_day)
    distance_by_day.sum { |day| day[1] }
  end

  def toponyms(points)
    CountriesAndCities.new(points).call
  end

  def current_stat(year, month)
    Stat.find_or_initialize_by(year:, month:, user:)
  end

  def create_stats_update_failed_notification(user, error)
    Notifications::Create.new(
      user:,
      kind: :error,
      title: 'Stats update failed',
      content: "#{error.message}, stacktrace: #{error.backtrace.join("\n")}"
    ).call
  end
end
