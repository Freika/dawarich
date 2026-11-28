# frozen_string_literal: true

module EnhancedImport
  module Adapters
    class SwarmAdapter < BaseAdapter
      SOURCE_LABEL = 'swarm'
      MAX_VISIT_DURATION = 2.hours
      MIN_VISIT_DURATION = 1.minute

      def translate
        return enum_for(:translate) unless block_given?

        checkins = Swarm::Checkins.parse(load_json_data)

        checkins.each_with_index do |checkin, index|
          next if checkin.venue_id.nil? || checkin.venue_name.nil?

          yield build_visit(checkin, checkins[index + 1])
        end
      end

      private

      def build_visit(checkin, next_checkin)
        place = Extracted::Place.new(
          external_place_id: "foursquare:#{checkin.venue_id}",
          name: checkin.venue_name,
          latitude: checkin.latitude,
          longitude: checkin.longitude,
          semantic_type: 'foursquare_venue'
        )

        Extracted::Visit.new(
          started_at: checkin.time,
          ended_at: ended_at(checkin, next_checkin),
          place: place,
          name: checkin.venue_name,
          confidence: nil,
          source_label: SOURCE_LABEL
        )
      end

      def ended_at(checkin, next_checkin)
        capped = checkin.time + MAX_VISIT_DURATION
        ended = next_checkin ? [next_checkin.time, capped].min : capped

        [ended, checkin.time + MIN_VISIT_DURATION].max
      end
    end
  end
end
