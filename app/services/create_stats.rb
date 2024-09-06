# frozen_string_literal: true

class CreateStats
  attr_reader :years, :months, :users

  def initialize(user_ids)
    @users = User.where(id: user_ids)
    @years = (1970..Time.current.year).to_a
    @months = (1..12).to_a
  end

  def call
    users.each do |user|
      years.each do |year|
        months.each { |month| update_month_stats(user, year, month) }
      end

      create_stats_updated_notification(user)
    rescue StandardError => e
      create_stats_update_failed_notification(user, e)
    end
  end

  private

  def points(user, beginning_of_month_timestamp, end_of_month_timestamp)
    user
      .tracked_points
      .without_raw_data
      .where(timestamp: beginning_of_month_timestamp..end_of_month_timestamp)
      .order(:timestamp)
      .select(:latitude, :longitude, :timestamp, :city, :country)
  end

  def update_month_stats(user, year, month)
    beginning_of_month_timestamp = DateTime.new(year, month).beginning_of_month.to_i
    end_of_month_timestamp = DateTime.new(year, month).end_of_month.to_i

    points = points(user, beginning_of_month_timestamp, end_of_month_timestamp)

    return if points.empty?

    stat = Stat.find_or_initialize_by(year:, month:, user:)
    stat.distance = distance(points)
    stat.toponyms = toponyms(points)
    stat.daily_distance = stat.distance_by_day
    stat.save
  end

  def distance(points)
    distance = 0

    points.each_cons(2) do
      distance += Geocoder::Calculations.distance_between(
        [_1.latitude, _1.longitude], [_2.latitude, _2.longitude], units: DISTANCE_UNIT.to_sym
      )
    end

    distance
  end

  def toponyms(points)
    CountriesAndCities.new(points).call
  end

  def create_stats_updated_notification(user)
    Notifications::Create.new(
      user:, kind: :info, title: 'Stats updated', content: 'Stats updated'
    ).call
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
