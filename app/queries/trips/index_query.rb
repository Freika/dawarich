# frozen_string_literal: true

module Trips
  class IndexQuery
    SORTS = {
      'newest' => 'trips.started_at DESC, trips.id DESC',
      'oldest' => 'trips.started_at ASC, trips.id ASC',
      'name' => 'lower(trips.name) ASC, trips.id ASC',
      'distance' => 'trips.distance DESC NULLS LAST, trips.id DESC'
    }.freeze
    DEFAULT_SORT = 'newest'
    QUERY_MAX_LENGTH = 100
    YEARS = (1900..2200)

    DESCRIPTION_TEXT_SQL = <<~SQL.squish
      replace(replace(replace(replace(replace(replace(
        regexp_replace(rich_texts.body, '<[^>]*>', ' ', 'g'),
        '&nbsp;', ' '), '&lt;', '<'), '&gt;', '>'), '&quot;', '"'), '&#39;', ''''), '&amp;', '&')
    SQL

    SEARCH_SQL = <<~SQL.squish
      trips.name ILIKE :pattern
      OR (
        jsonb_typeof(trips.visited_countries) = 'array'
        AND EXISTS (
          SELECT 1 FROM jsonb_array_elements_text(trips.visited_countries) AS visited(country)
          WHERE visited.country ILIKE :pattern
        )
      )
      OR EXISTS (
        SELECT 1 FROM action_text_rich_texts rich_texts
        WHERE rich_texts.record_type = 'Trip' AND rich_texts.record_id = trips.id
          AND rich_texts.name = 'description'
          AND #{DESCRIPTION_TEXT_SQL} ILIKE :pattern
      )
      OR EXISTS (
        SELECT 1 FROM notes
        WHERE notes.attachable_type = 'Trip' AND notes.attachable_id = trips.id
          AND (notes.title ILIKE :pattern OR notes.body ILIKE :pattern)
      )
      OR EXISTS (
        SELECT 1 FROM planned_days
        WHERE planned_days.trip_id = trips.id
          AND (
            planned_days.title ILIKE :pattern OR planned_days.notes ILIKE :pattern
            OR EXISTS (
              SELECT 1 FROM planned_stops
              WHERE planned_stops.planned_day_id = planned_days.id
                AND (planned_stops.name ILIKE :pattern OR planned_stops.address ILIKE :pattern
                     OR planned_stops.notes ILIKE :pattern)
            )
          )
      )
      OR EXISTS (
        SELECT 1 FROM planned_unplanned_places places
        WHERE places.trip_id = trips.id
          AND (places.name ILIKE :pattern OR places.address ILIKE :pattern OR places.notes ILIKE :pattern)
      )
      OR EXISTS (
        SELECT 1 FROM planned_accommodations stays
        WHERE stays.trip_id = trips.id
          AND (stays.name ILIKE :pattern OR stays.address ILIKE :pattern OR stays.notes ILIKE :pattern)
      )
      OR EXISTS (
        SELECT 1 FROM planned_reservations bookings
        WHERE bookings.trip_id = trips.id
          AND (bookings.title ILIKE :pattern OR bookings.location ILIKE :pattern OR bookings.notes ILIKE :pattern)
      )
    SQL

    Filters = Data.define(:q, :sort, :year, :month, :country) do
      def active?
        q.present? || year.present? || country.present?
      end
    end

    attr_reader :filters

    def initialize(user, params)
      @user = user
      @filters = parse(params)
    end

    def call
      scope = user.trips
      scope = search(scope) if filters.q.present?
      scope = within_period(scope) if filters.year
      scope = visiting(scope) if filters.country.present?
      scope.order(Arel.sql(SORTS.fetch(filters.sort)))
    end

    def years
      user.trips.pluck(:started_at, :ended_at).flat_map do |started_at, ended_at|
        (started_at.in_time_zone(time_zone).year..ended_at.in_time_zone(time_zone).year).to_a
      end.uniq.sort.reverse
    end

    def countries
      user.trips
          .where("jsonb_typeof(trips.visited_countries) = 'array'")
          .distinct
          .pluck(Arel.sql('jsonb_array_elements_text(trips.visited_countries)'))
          .sort_by(&:downcase)
    end

    private

    attr_reader :user

    def parse(params)
      year = Integer(params[:year].to_s, 10, exception: false)
      year = nil unless YEARS.cover?(year)
      month = Integer(params[:month].to_s, 10, exception: false) if year
      month = nil unless (1..12).cover?(month)

      Filters.new(
        q: params[:q].to_s.delete("\0").strip[0, QUERY_MAX_LENGTH],
        sort: SORTS.key?(params[:sort]) ? params[:sort] : DEFAULT_SORT,
        year:,
        month:,
        country: params[:country].to_s.delete("\0").strip.presence
      )
    end

    def search(scope)
      pattern = "%#{ActiveRecord::Base.sanitize_sql_like(filters.q)}%"
      scope.where(SEARCH_SQL, pattern:)
    end

    def within_period(scope)
      period_start = time_zone.local(filters.year, filters.month || 1, 1)
      period_end = filters.month ? period_start.next_month : period_start.next_year
      scope.where('trips.started_at < ? AND trips.ended_at >= ?', period_end, period_start)
    end

    def visiting(scope)
      scope.where("jsonb_typeof(trips.visited_countries) = 'array'")
           .where('trips.visited_countries @> ?::jsonb', [filters.country].to_json)
    end

    def time_zone
      @time_zone ||= ActiveSupport::TimeZone[user.timezone_iana] || Time.zone
    end
  end
end
