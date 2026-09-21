# frozen_string_literal: true

module Visits
  module Detection
    # Labels a detected stay — attribution, not detection. Evidence order:
    # a containing Place > a POI voted from the
    # stay's own reverse-geocoded points > a bare address.
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
        area = unmapped_containing_area(stay)
        if area
          place = Places::LegacyAreaAdapter.new(user: user).resolve(area)
          remember_visit_radius(place)
          return { area: nil, place: place, name: place.name, location_label: place.name, evidence: :place }
        end

        place = containing_place(stay)
        return { area: nil, place: place, name: place.name, location_label: place.name, evidence: :place } if place

        poi_name = poi_vote(stay)
        lookup = poi_name ? nil : reverse_lookup(stay)
        poi_name ||= venue_name(stay, lookup)
        if poi_name
          minted = PlaceFinder.new(user).find_or_create_place(
            center_lat: stay[:center_lat], center_lon: stay[:center_lon], suggested_name: poi_name
          )
          remember_visit_radius(minted)
          return { area: nil, place: minted, name: poi_name, location_label: poi_name, evidence: :poi }
        end

        address = address_name(lookup)
        return { area: nil, place: nil, name: address, location_label: address, evidence: :address } if address

        { area: nil, place: nil, name: nil, evidence: :none }
      end

      private

      attr_reader :user, :policy

      # Keeps Areas functional while the async migration is draining. Once an
      # Area has a mapping, its Place participates in the canonical path below.
      def unmapped_containing_area(stay)
        user.areas.where.not(id: LegacyAreaPlaceMapping.select(:area_id)).find do |area|
          distance_m(stay[:center_lat], stay[:center_lon], area.latitude, area.longitude) <= area.radius
        end
      end

      def containing_place(stay)
        return nil unless max_visit_radius.positive?

        candidates = user.places
                         .near([stay[:center_lat], stay[:center_lon]], max_visit_radius, :m)
                         .containing(stay[:center_lat], stay[:center_lon])
                         .to_a
        return nil if candidates.empty?

        candidates.min_by do |place|
          [
            place.visit_radius,
            distance_m(stay[:center_lat], stay[:center_lon], place.lat, place.lon),
            place.id
          ]
        end
      end

      def max_visit_radius
        return @max_visit_radius if defined?(@max_visit_radius)

        @max_visit_radius = user.places.maximum(:visit_radius).to_i
      end

      def remember_visit_radius(place)
        @max_visit_radius = [max_visit_radius, place.visit_radius].max
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
        return nil if result.blank?

        Geocoding::ResultNormalizer.call(result)
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
