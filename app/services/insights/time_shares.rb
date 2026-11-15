# frozen_string_literal: true

module Insights
  # Where the days and hours of a year went, for the Insights donuts. Read from
  # visits, tracks, trips and homes; the points table is far too large to scan
  # on a page view.
  #
  # Days of the year so far:
  # - trip: covered by a Trip;
  # - home: tracked, with visits only at the Home of that date and no movement;
  # - out: tracked otherwise (a visit elsewhere, or any track);
  # - untracked: everything else.
  # Hours: visits at home, visits at other places, time in tracks, and the rest.
  # A visit or track counts toward the day it starts on.
  class TimeShares
    Result = Struct.new(:days, :hours, keyword_init: true)

    def initialize(user, year, today: Time.zone.today)
      @user = user
      @year = year.to_i
      @today = today
    end

    def call
      first = Date.new(year, 1, 1)
      last = [Date.new(year, 12, 31), today].min
      return if last < first

      range = first.beginning_of_day..last.end_of_day
      Result.new(days: days(first..last, range), hours: hours((last - first + 1) * 24, range))
    end

    private

    attr_reader :user, :year, :today

    def days(dates, range)
      trip_days = trips(range).flat_map { |started, ended| (started.to_date..ended.to_date).to_a }.to_set & dates.to_set
      tracked = Set.new
      out = Set.new
      visits(range).each do |place_id, started, _ended|
        day = started.to_date
        tracked << day
        out << day unless home?(place_id, day)
      end
      tracks(range).map(&:first).each do |started|
        tracked << started.to_date
        out << started.to_date
      end

      tracked -= trip_days
      { home: (tracked - out).size, out: (tracked & out).size, trip: trip_days.size,
        untracked: dates.count - tracked.size - trip_days.size }
    end

    def hours(total, range)
      spent = Hash.new(0.0)
      visits(range).each do |place_id, started, ended|
        spent[home?(place_id, started.to_date) ? :home : :places] += (ended - started) / 3600.0
      end
      spent[:moving] = tracks(range).sum { |started, ended| (ended - started) / 3600.0 }
      known = spent.values.sum
      { home: spent[:home].round(1), places: spent[:places].round(1), moving: spent[:moving].round(1),
        no_data: [total - known, 0].max.round(1) }
    end

    def visits(range)
      @visits ||= user.scoped_visits.where.not(status: :declined).where(started_at: range)
                      .pluck(:place_id, :started_at, :ended_at)
    end

    def tracks(range)
      @tracks ||= user.scoped_tracks.where(start_at: range).pluck(:start_at, :end_at)
    end

    def trips(range)
      user.trips.where('started_at <= ? AND ended_at >= ?', range.end, range.begin).pluck(:started_at, :ended_at)
    end

    def home?(place_id, day)
      @homes ||= user.homes.pluck(:place_id, :started_on, :ended_on)
      @homes.any? do |home_place_id, started_on, ended_on|
        home_place_id == place_id && (started_on.nil? || started_on <= day) && (ended_on.nil? || day <= ended_on)
      end
    end
  end
end
