# frozen_string_literal: true

module Visits
  module Detection
    # Labels a detected stay — attribution, not detection. Evidence order:
    # containing user area > nearby known place (manual-first, history-boosted)
    # > POI voted from the stay's own reverse-geocoded points > bare address.
    # Below the POI gate no Place row is minted and no business name is
    # claimed: a visit the data can't support gets a street address, not a
    # restaurant. Must never run inside a DB transaction (geocoder I/O).
    class PlaceAttributor
      def initialize(user, policy)
        @user = user
        @policy = policy
      end

      # OSM keys that describe ways and land, not venues — a stay may be ON
      # them but never AT them.
      STREETISH_OSM_KEYS = %w[highway place boundary landuse natural waterway railway].freeze

      def call(stay)
        area = containing_area(stay)
        return { area: area, place: nil, name: area.name, evidence: :area } if area

        place = known_place(stay)
        return { area: nil, place: place, name: place.name, evidence: :place } if place

        poi_name = poi_vote(stay)
        lookup = poi_name ? nil : reverse_lookup(stay)
        poi_name ||= venue_name(stay, lookup)
        if poi_name
          minted = PlaceFinder.new(user).find_or_create_place(
            center_lat: stay[:center_lat], center_lon: stay[:center_lon], suggested_name: poi_name
          )
          return { area: nil, place: minted, name: poi_name, evidence: :poi }
        end

        address = address_name(lookup)
        return { area: nil, place: nil, name: address, evidence: :address } if address

        { area: nil, place: nil, name: nil, evidence: :none }
      end

      private

      attr_reader :user, :policy

      def containing_area(stay)
        user.areas.find do |area|
          distance_m(stay[:center_lat], stay[:center_lon], area.latitude, area.longitude) <= area.radius
        end
      end

      # Manual curation outranks everything; among equals the user's own
      # confirmed history, then plain distance.
      def known_place(stay)
        candidates = user.places
                         .near([stay[:center_lat], stay[:center_lon]], policy.attribution_radius_m, :m)
                         .to_a
        return nil if candidates.empty?

        history = user.visits.active.confirmed
                      .where(place_id: candidates.map(&:id))
                      .group(:place_id).count

        candidates.min_by do |place|
          [
            place.manual? ? 0 : 1,
            -history.fetch(place.id, 0),
            distance_m(stay[:center_lat], stay[:center_lon], place.lat, place.lon)
          ]
        end
      end

      def poi_vote(stay)
        return nil if stay[:point_ids].blank?

        geodata_points = user.points.where(id: stay[:point_ids]).where.not(geodata: {}).select(:id, :geodata)
        return nil if geodata_points.empty?

        Visits::Names::Suggester.new(geodata_points).call
      end

      def reverse_lookup(stay)
        return nil unless Geocoding::Config.for(user).enabled?

        result = Geocoding::Search.call(user: user, query: [stay[:center_lat], stay[:center_lon]],
                                        limit: 1, distance_sort: true, units: :km).first
        data = result&.data
        return nil if data.blank?

        data = data.deep_stringify_keys if data.is_a?(Hash)
        {
          properties: data['properties'] || data.dig('features', 0, 'properties'),
          coords: data.dig('geometry', 'coordinates') || data.dig('features', 0, 'geometry', 'coordinates')
        }
      rescue StandardError => e
        Rails.logger.warn("[Visits::Detection::PlaceAttributor] reverse lookup failed: #{e.class}: #{e.message}")
        nil
      end

      # A reverse-geocoded feature counts as a venue only when it is an actual
      # named non-street thing that verifiably sits inside the stay — the
      # nearest-POI guess that named road clusters after restaurants does not
      # clear this bar.
      def venue_name(stay, lookup)
        properties = lookup&.dig(:properties)
        return nil if properties.blank? || properties['name'].blank?
        return nil if STREETISH_OSM_KEYS.include?(properties['osm_key'])
        return nil unless venue_inside_stay?(stay, lookup[:coords])

        properties['name']
      end

      def venue_inside_stay?(stay, coords)
        return false if coords.blank?

        lon, lat = coords
        distance_m(stay[:center_lat], stay[:center_lon], lat, lon) <=
          [stay[:radius].to_i, policy.attribution_radius_m].max
      end

      def address_name(lookup)
        properties = lookup&.dig(:properties)
        return nil if properties.blank?

        street_line = [properties['street'], properties['housenumber']].compact_blank.join(' ')
        return street_line if street_line.present?

        # For street-ish features the OSM name IS the address-flavored name.
        properties['name'] if STREETISH_OSM_KEYS.include?(properties['osm_key'])
      end

      def distance_m(lat1, lon1, lat2, lon2)
        Geocoder::Calculations.distance_between([lat1, lon1], [lat2, lon2], units: :km) * 1000
      end
    end
  end
end
