# frozen_string_literal: true

module McpTools
  class SearchVisits < BaseTool
    DEFAULT_LIMIT = 20
    MAX_LIMIT = 50

    tool_name 'search_visits'
    title 'Search visits'
    description "Find the authenticated user's visits whose name, place, city, country or area matches " \
                'a text query, newest first, with the total number of matches.'
    annotations(
      read_only_hint: true,
      destructive_hint: false,
      idempotent_hint: true,
      open_world_hint: false
    )
    input_schema(
      properties: {
        query: {
          type: 'string',
          minLength: 2,
          description: 'Case-insensitive text matched against visit, place, city, country and area names.'
        },
        limit: {
          type: 'integer',
          minimum: 1,
          maximum: MAX_LIMIT,
          description: "Maximum number of visits to return; defaults to #{DEFAULT_LIMIT}."
        }
      },
      required: %w[query]
    )
    output_schema(
      type: 'object',
      additionalProperties: false,
      properties: {
        total_count: { type: 'integer' },
        visits: { type: 'array', items: TimelineSerializer::ENTRY_SCHEMA }
      },
      required: %w[total_count visits],
      '$defs': TimelineSerializer::DEFS
    )

    class << self
      def call(query:, server_context:, limit: DEFAULT_LIMIT)
        user = server_context.fetch(:user)
        visits = matching_visits(user, query)

        Time.use_zone(user.safe_settings.timezone) do
          success(
            total_count: visits.count,
            visits: visits.preload(:place, :area)
                          .order(started_at: :desc)
                          .limit(limit)
                          .map { |visit| TimelineSerializer.entry(timeline_entry(visit)) }
          )
        end
      end

      private

      def matching_visits(user, query)
        user.scoped_visits.left_joins(:place, :area).where(
          'visits.name ILIKE :pattern OR places.name ILIKE :pattern OR places.city ILIKE :pattern ' \
          'OR places.country ILIKE :pattern OR areas.name ILIKE :pattern',
          pattern: "%#{Visit.sanitize_sql_like(query)}%"
        )
      end

      def timeline_entry(visit)
        {
          type: 'visit',
          name: visit.name,
          status: visit.status,
          started_at: visit.started_at.iso8601,
          ended_at: visit.ended_at.iso8601,
          duration: visit.duration,
          place: visit.place && {
            name: visit.place.name,
            lat: visit.place.lat,
            lng: visit.place.lon,
            city: visit.place.city,
            country: visit.place.country
          },
          area: visit.area && {
            name: visit.area.name,
            lat: visit.area.latitude,
            lng: visit.area.longitude,
            radius: visit.area.radius
          }
        }
      end
    end
  end
end
