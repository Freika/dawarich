# frozen_string_literal: true

class CreateStats
  attr_reader :years, :months, :user

  def initialize(user_id)
    @user = User.find(user_id)
    @years = (1970..Time.current.year).to_a
    @months = (1..12).to_a
  end

  def call
    years.flat_map do |year|
      months.map do |month|
        beginning_of_month_timestamp = DateTime.new(year, month).beginning_of_month.to_i
        end_of_month_timestamp = DateTime.new(year, month).end_of_month.to_i

        points = points(beginning_of_month_timestamp, end_of_month_timestamp)
        next if points.empty?

        stat = Stat.create(year:, month:, user:, distance: distance(points), toponyms: toponyms(points))

        stat.update(daily_distance: stat.distance_by_day) if stat.persisted?

        stat
      end
    end.compact
  end

  private

  def points(beginning_of_month_timestamp, end_of_month_timestamp)
    Point
      .where(timestamp: beginning_of_month_timestamp..end_of_month_timestamp)
      .order(:timestamp)
      .select(:latitude, :longitude, :timestamp, :city, :country)
  end

  def distance(points)
    km = 0

    points.each_cons(2) do
      km += Geocoder::Calculations.distance_between(
        [_1.latitude, _1.longitude], [_2.latitude, _2.longitude], units: :km
      )
    end

    km
  end

  def toponyms(points)
    CountriesAndCities.new(points).call
  end
end
