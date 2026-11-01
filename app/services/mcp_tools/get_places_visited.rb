# frozen_string_literal: true

module McpTools
  class GetPlacesVisited < BaseTool
    tool_name 'get_places_visited'
    title 'Get places visited'
    description 'Return the countries and cities the authenticated user spent time in during a year, or one month of ' \
                'it, with the minutes spent in each, longest first. City names come from reverse geocoding, so one ' \
                'city can appear under more than one spelling or language. Use get_travel_stats to find the years ' \
                'and months that have data.'
    annotations(
      read_only_hint: true,
      destructive_hint: false,
      idempotent_hint: true,
      open_world_hint: false
    )
    input_schema(
      properties: {
        year: { type: 'integer', minimum: 1970, maximum: 2100 },
        month: { type: 'integer', minimum: 1, maximum: 12, description: 'Limit the result to this month of year.' }
      },
      required: %w[year],
      additionalProperties: false
    )
    output_schema(
      type: 'object',
      additionalProperties: false,
      properties: {
        year: { type: 'integer' },
        month: { type: %w[integer null] },
        countries: {
          type: 'array',
          items: {
            type: 'object',
            additionalProperties: false,
            properties: {
              name: { type: 'string' },
              minutes: { type: 'integer' },
              cities: {
                type: 'array',
                items: {
                  type: 'object',
                  additionalProperties: false,
                  properties: { name: { type: 'string' }, minutes: { type: 'integer' }, points: { type: 'integer' } },
                  required: %w[name minutes points]
                }
              }
            },
            required: %w[name minutes cities]
          }
        }
      },
      required: %w[year month countries]
    )

    class << self
      def call(year:, server_context:, month: nil)
        stats = server_context.fetch(:user).scoped_stats.select(:id, :toponyms).where(year:)
        stats = stats.where(month:) if month

        success(year:, month:, countries: countries(stats))
      end

      private

      def countries(stats)
        rows = StatToponyms.countries(stats).map do |country, cities|
          city_rows = cities.map { |city, totals| { name: city, **totals } }.sort_by { |row| -row[:minutes] }

          { name: country, minutes: city_rows.sum { |row| row[:minutes] }, cities: city_rows }
        end
        rows.sort_by { |row| -row[:minutes] }
      end
    end
  end
end
