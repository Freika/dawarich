# frozen_string_literal: true

module EnhancedImport
  module Writers
    class PlaceWriter
      def initialize(user, import, source: :photon)
        @user = user
        @import = import
        @source = source
      end

      NEARBY_METERS = 75

      def upsert(extracted)
        existing = find_by_external_id(extracted) || find_nearby(extracted)
        if existing
          attach_tag(existing, extracted)
          return [existing, false]
        end

        place = Place.create!(
          user_id: @user.id,
          import_id: @import.id,
          name: extracted.name.presence || 'Unknown',
          latitude: extracted.latitude,
          longitude: extracted.longitude,
          lonlat: "POINT(#{extracted.longitude} #{extracted.latitude})",
          source: @source,
          geodata: build_geodata(extracted)
        )
        attach_tag(place, extracted)
        [place, true]
      rescue ActiveRecord::RecordNotUnique
        existing = Place.where(user_id: @user.id)
                        .where("geodata ->> 'external_place_id' = ?", extracted.external_place_id)
                        .first
        [existing, false]
      end

      private

      def attach_tag(place, extracted)
        return if extracted.tag_name.blank?

        tag = existing_tag(extracted.tag_name)
        return if tag&.privacy_zone?

        tag ||= create_tag(extracted)
        return if tag.nil?

        place.add_tag(tag)
      end

      def existing_tag(name)
        @user.tags.where('LOWER(tags.name) = ?', name.downcase).first
      end

      def create_tag(extracted)
        @user.tags.create!(name: extracted.tag_name, color: extracted.tag_color)
      rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique
        existing_tag(extracted.tag_name)
      end

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
