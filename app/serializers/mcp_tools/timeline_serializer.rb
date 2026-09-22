# frozen_string_literal: true

module McpTools
  class TimelineSerializer
    DEFS = {
      location: {
        type: %w[object null],
        additionalProperties: false,
        properties: {
          name: { type: %w[string null] },
          latitude: { type: 'number' },
          longitude: { type: 'number' },
          city: { type: %w[string null] },
          country: { type: %w[string null] }
        },
        required: %w[name latitude longitude city country]
      },
      area: {
        type: %w[object null],
        additionalProperties: false,
        properties: {
          name: { type: 'string' },
          latitude: { type: 'number' },
          longitude: { type: 'number' },
          radius: { type: 'number' }
        },
        required: %w[name latitude longitude radius]
      }
    }.freeze

    ENTRY_SCHEMA = {
      type: 'object',
      additionalProperties: false,
      properties: {
        type: { type: 'string', enum: %w[visit journey] },
        name: { type: %w[string null] },
        status: { type: 'string' },
        started_at: { type: 'string', format: 'date-time' },
        ended_at: { type: 'string', format: 'date-time' },
        duration_minutes: { type: 'number' },
        continuation_of_date: {
          type: %w[string null],
          format: 'date',
          description: 'Start date of a journey listed in full on that date; this row is its part after midnight.'
        },
        place: { '$ref': '#/$defs/location' },
        area: { '$ref': '#/$defs/area' },
        distance: { type: 'number' },
        distance_unit: { type: 'string', enum: %w[km mi] },
        dominant_mode: { type: %w[string null] },
        average_speed: { type: 'number' },
        speed_unit: { type: 'string' }
      },
      required: %w[type started_at ended_at duration_minutes]
    }.freeze

    OUTPUT_SCHEMA = {
      type: 'object',
      additionalProperties: false,
      properties: {
        days: {
          type: 'array',
          items: {
            type: 'object',
            additionalProperties: false,
            properties: {
              date: { type: 'string', format: 'date' },
              summary: {
                type: 'object',
                additionalProperties: false,
                properties: {
                  total_distance: { type: 'number' },
                  distance_unit: { type: 'string', enum: %w[km mi] },
                  places_visited: { type: 'integer' },
                  time_moving_minutes: { type: 'integer' },
                  time_stationary_minutes: { type: 'integer' }
                },
                required: %w[total_distance distance_unit places_visited time_moving_minutes time_stationary_minutes]
              },
              entries: { type: 'array', items: ENTRY_SCHEMA }
            },
            required: %w[date summary entries]
          }
        }
      },
      required: ['days'],
      '$defs': DEFS
    }.freeze

    class << self
      def call(days)
        { days: days.map { |day| serialize_day(day) } }
      end

      def entry(entry)
        common = {
          type: entry.fetch(:type),
          started_at: entry.fetch(:started_at),
          ended_at: entry.fetch(:ended_at)
        }

        entry[:type] == 'visit' ? common.merge(serialize_visit(entry)) : common.merge(serialize_journey(entry))
      end

      private

      def serialize_day(day)
        {
          date: day.fetch(:date),
          summary: serialize_summary(day.fetch(:summary)),
          entries: day.fetch(:entries).map { |day_entry| entry(day_entry) }
        }
      end

      def serialize_summary(summary)
        {
          total_distance: summary.fetch(:total_distance).to_f,
          distance_unit: summary.fetch(:distance_unit),
          places_visited: summary.fetch(:places_visited).to_i,
          time_moving_minutes: summary.fetch(:time_moving_minutes).to_i,
          time_stationary_minutes: summary.fetch(:time_stationary_minutes).to_i
        }
      end

      def serialize_visit(entry)
        {
          name: entry[:name],
          status: entry.fetch(:status),
          duration_minutes: entry.fetch(:duration).to_f,
          place: serialize_location(entry[:place]),
          area: serialize_area(entry[:area])
        }
      end

      def serialize_journey(entry)
        {
          continuation_of_date: entry[:continuation_of_date],
          duration_minutes: ((entry[:day_duration] || entry.fetch(:duration)).to_f / 60).round(1),
          distance: (entry[:day_distance] || entry.fetch(:distance)).to_f,
          distance_unit: entry.fetch(:distance_unit),
          dominant_mode: entry[:dominant_mode],
          average_speed: entry.fetch(:avg_speed).to_f,
          speed_unit: entry.fetch(:speed_unit)
        }
      end

      def serialize_location(location)
        return unless location

        {
          name: location[:name],
          latitude: location.fetch(:lat).to_f,
          longitude: location.fetch(:lng).to_f,
          city: location[:city],
          country: location[:country]
        }
      end

      def serialize_area(area)
        return unless area

        {
          name: area.fetch(:name),
          latitude: area.fetch(:lat).to_f,
          longitude: area.fetch(:lng).to_f,
          radius: area.fetch(:radius).to_f
        }
      end
    end
  end
end
