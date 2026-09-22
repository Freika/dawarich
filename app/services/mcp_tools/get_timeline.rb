# frozen_string_literal: true

module McpTools
  class GetTimeline < BaseTool
    MAX_RANGE_DAYS = 7
    MAX_ENTRIES = 250

    tool_name 'get_timeline'
    title 'Get timeline'
    description "Return the authenticated user's visits and journeys for a bounded time range. " \
                'A journey that crosses midnight is listed in full on its start date and again, for the part ' \
                'after midnight, on later dates with continuation_of_date set. When adding up journeys across ' \
                'days, skip a continuation row whose continuation_of_date is also in the result, or use each ' \
                "day's summary. #{VISIT_STATUS_NOTE}"
    annotations(
      read_only_hint: true,
      destructive_hint: false,
      idempotent_hint: true,
      open_world_hint: false
    )
    input_schema(
      properties: {
        start_at: { type: 'string', description: 'Range start as an ISO 8601 date or timestamp.' },
        end_at: { type: 'string', description: 'Inclusive range end as an ISO 8601 date or timestamp.' },
        distance_unit: { type: 'string', enum: %w[km mi], description: 'Distance unit; defaults to the user setting.' }
      },
      required: %w[start_at end_at],
      additionalProperties: false
    )
    output_schema(TimelineSerializer::OUTPUT_SCHEMA)

    class << self
      def call(start_at:, end_at:, server_context:, distance_unit: nil)
        user = server_context.fetch(:user)
        Time.use_zone(user.safe_settings.timezone) do
          range = parse_range(start_at, end_at)
          next range if range.is_a?(MCP::Tool::Response)

          days = assemble_days(user, range, distance_unit)
          if days.sum { |day| day.fetch(:entries).size } > MAX_ENTRIES
            next failure("Timeline contains more than #{MAX_ENTRIES} entries; request a smaller range")
          end

          success(TimelineSerializer.call(days))
        end
      end

      private

      def assemble_days(user, range, distance_unit)
        Timeline::DayAssembler.new(
          user,
          start_at: range.fetch(:start_at).iso8601(6),
          end_at: range.fetch(:end_at).iso8601(6),
          distance_unit: distance_unit.presence || user.safe_settings.distance_unit
        ).call
      end

      def parse_range(start_at, end_at)
        range_start = parse_boundary(start_at, end_of_day: false)
        range_end = parse_boundary(end_at, end_of_day: true)
        return failure('end_at must not be earlier than start_at') if range_end < range_start

        calendar_days = (range_end.to_date - range_start.to_date).to_i + 1
        return failure("Date range cannot exceed #{MAX_RANGE_DAYS} calendar days") if calendar_days > MAX_RANGE_DAYS

        { start_at: range_start, end_at: range_end }
      rescue ArgumentError, TypeError
        failure('start_at and end_at must be valid ISO 8601 dates or timestamps')
      end

      def parse_boundary(value, end_of_day:)
        raise ArgumentError if value.blank?

        if value.match?(/\A\d{4}-\d{2}-\d{2}\z/)
          date = Date.iso8601(value)
          return end_of_day ? date.in_time_zone.end_of_day : date.in_time_zone.beginning_of_day
        end

        DateTime.iso8601(value)
        Time.zone.iso8601(value)
      end
    end
  end
end
