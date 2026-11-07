# frozen_string_literal: true

module McpTools
  class GetTravelStats < BaseTool
    SUMMARY_PROPERTIES = {
      distance: { type: 'number', description: 'Distance travelled, including flight_distance.' },
      flight_distance: { type: 'number', description: 'Part of distance covered by flights.' },
      countries: { type: 'array', items: { type: 'string' } },
      cities_count: { type: 'integer' }
    }.freeze

    tool_name 'get_travel_stats'
    title 'Get travel stats'
    description "Return the authenticated user's distance travelled and the countries they spent time in, with one " \
                'row per year across their whole history, or one row per month when a year is given. Use it for ' \
                'totals such as distance in a year or countries visited; use get_places_visited for the cities. ' \
                'Figures come from monthly stats, which Dawarich recalculates in the background after new points ' \
                'arrive, so the latest month can lag slightly.'
    annotations(
      read_only_hint: true,
      destructive_hint: false,
      idempotent_hint: true,
      open_world_hint: false
    )
    input_schema(
      properties: {
        year: { type: 'integer', minimum: 1970, maximum: 2100, description: 'Break this year down by month.' },
        distance_unit: { type: 'string', enum: %w[km mi], description: 'Distance unit; defaults to the user setting.' }
      },
      additionalProperties: false
    )
    output_schema(
      type: 'object',
      additionalProperties: false,
      properties: {
        distance_unit: { type: 'string' },
        year: { type: %w[integer null] },
        total: {
          type: 'object',
          additionalProperties: false,
          properties: SUMMARY_PROPERTIES,
          required: SUMMARY_PROPERTIES.keys.map(&:to_s)
        },
        periods: {
          type: 'array',
          items: {
            type: 'object',
            additionalProperties: false,
            properties: { year: { type: 'integer' }, month: { type: %w[integer null] }, **SUMMARY_PROPERTIES },
            required: %w[year month] + SUMMARY_PROPERTIES.keys.map(&:to_s)
          }
        }
      },
      required: %w[distance_unit year total periods]
    )

    class << self
      def call(server_context:, year: nil, distance_unit: nil)
        user = server_context.fetch(:user)
        unit = distance_unit.presence || user.safe_settings.distance_unit
        stats = user.scoped_stats.select(:id, :year, :month, :distance, :flight_distance, :toponyms)
        stats = stats.where(year:) if year
        stats = stats.order(:year, :month).to_a
        periods = stats.group_by { |stat| [stat.year, year ? stat.month : nil] }

        success(
          distance_unit: unit,
          year: year,
          total: summary(stats, unit),
          periods: periods.map { |(period_year, month), rows| { year: period_year, month:, **summary(rows, unit) } }
        )
      end

      private

      def summary(stats, unit)
        countries = StatToponyms.countries(stats)

        {
          distance: in_unit(stats.sum(&:distance), unit),
          flight_distance: in_unit(stats.sum(&:flight_distance), unit),
          countries: countries.keys.sort,
          cities_count: countries.values.sum(&:size)
        }
      end

      def in_unit(meters, unit)
        (meters.to_f / ::DISTANCE_UNITS.fetch(unit.to_sym)).round(1)
      end
    end
  end
end
