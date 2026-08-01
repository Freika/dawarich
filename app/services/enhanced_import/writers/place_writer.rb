# frozen_string_literal: true

module EnhancedImport
  module Writers
    class PlaceWriter
      def initialize(user, import)
        @user = user
        @import = import
      end

      NEARBY_METERS = 75

      def upsert(extracted)
        existing = find_by_external_id(extracted) || find_nearby(extracted)
        return [existing, false] if existing

        place = Place.create!(
          user_id: @user.id,
          import_id: @import.id,
          name: extracted.name.presence || 'Unknown',
          latitude: extracted.latitude,
          longitude: extracted.longitude,
          lonlat: "POINT(#{extracted.longitude} #{extracted.latitude})",
          source: :photon,
          geodata: build_geodata(extracted)
        )
        [place, true]
      rescue ActiveRecord::RecordNotUnique
        existing = Place.where(user_id: @user.id)
                        .where("geodata ->> 'external_place_id' = ?", extracted.external_place_id)
                        .first
        [existing, false]
      end

      private

      def find_by_external_id(extracted)
        Place.where(user_id: @user.id)
             .where("geodata ->> 'external_place_id' = ?", extracted.external_place_id)
             .first
      end

      # Without this, a Google "Home" lands on the map beside the place Dawarich
      # already geocoded at the same spot. Names must agree before reusing a row,
      # or two genuinely different places within 75 m would collapse into one.
      def find_nearby(extracted)
        name = extracted.name.to_s.strip
        return nil if name.empty?

        lon = extracted.longitude.to_f
        lat = extracted.latitude.to_f

        Place.where(user_id: @user.id)
             .where('LOWER(places.name) = ?', name.downcase)
             .where(
               'ST_DWithin(places.lonlat::geography, ST_SetSRID(ST_MakePoint(?, ?), 4326)::geography, ?)',
               lon, lat, NEARBY_METERS
             )
             .order(Arel.sql(
                      ActiveRecord::Base.sanitize_sql_array(
                        ['places.lonlat::geography <-> ST_SetSRID(ST_MakePoint(?, ?), 4326)::geography', lon, lat]
                      )
                    ))
             .first
      end

      def build_geodata(extracted)
        {
          'external_place_id' => extracted.external_place_id,
          'semantic_type' => extracted.semantic_type
        }.merge(extracted.geodata_extras || {}).compact
      end
    end
  end
end
