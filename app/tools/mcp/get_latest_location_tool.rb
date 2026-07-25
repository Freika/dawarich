# frozen_string_literal: true

module Mcp
  class GetLatestLocationTool < BaseTool
    tool_name 'get_latest_location'
    title 'Get latest location'
    description 'Return the authenticated users newest visible non-anomalous location point.'
    annotations(
      read_only_hint: true,
      destructive_hint: false,
      idempotent_hint: true,
      open_world_hint: false
    )
    input_schema(properties: {})
    output_schema(
      properties: {
        point: {
          type: %w[object null],
          properties: {
            id: { type: 'integer' },
            latitude: { type: 'number' },
            longitude: { type: 'number' },
            recorded_at: { type: 'string', format: 'date-time' },
            country_name: { type: 'string' },
            velocity: { type: %w[number null] },
            tracker_id: { type: %w[string null] }
          }
        }
      },
      required: ['point']
    )

    class << self
      def call(server_context:)
        point = server_context.fetch(:user)
                              .scoped_points
                              .not_anomaly
                              .without_raw_data
                              .order(timestamp: :desc)
                              .first

        success(point: point && serialize(point))
      end

      private

      def serialize(point)
        {
          id: point.id,
          latitude: point.lat.to_f,
          longitude: point.lon.to_f,
          recorded_at: Time.zone.at(point.timestamp).iso8601,
          country_name: point.country_name,
          velocity: point.velocity.presence&.to_f,
          tracker_id: point.tracker_id
        }
      end
    end
  end
end
