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
        renamed = nil
        existing = find_by_external_id(extracted)
        existing ||= (renamed = find_renamed_waypoint(extracted))
        existing ||= find_nearby(extracted)

        if existing
          claim(existing)
          renamed ? adopt_rename(existing, extracted) : adopt_identity(existing, extracted)
          attach_tag(existing, extracted)
          return [existing, false]
        end

        place = Place.create!(
          user_id: @user.id,
          import_id: @import.id,
          name: place_name(extracted),
          latitude: extracted.latitude,
          longitude: extracted.longitude,
          lonlat: "POINT(#{extracted.longitude} #{extracted.latitude})",
          source: @source,
          geodata: build_geodata(extracted)
        )
        claim(place)
        attach_tag(place, extracted)
        [place, true]
      rescue ActiveRecord::RecordNotUnique
        existing = find_by_external_id(extracted)
        if existing
          claim(existing)
          attach_tag(existing, extracted)
        end
        [existing, false]
      end

      private

      NAME_LIMIT = 255
      SAME_PIN_METERS = 1
      SAME_PIN_CANDIDATE_LIMIT = 10

      def claim(place)
        claimed_ids << place.id
      end

      def claimed_ids
        @claimed_ids ||= Set.new
      end

      def find_renamed_waypoint(extracted)
        return unless @source.to_s == 'gpx_waypoint'

        rows = Place.where(user_id: @user.id, source: Place.sources[:gpx_waypoint])
                    .where(
                      'ST_DWithin(places.lonlat::geography, ST_SetSRID(ST_MakePoint(?, ?), 4326)::geography, ?)',
                      extracted.longitude.to_f, extracted.latitude.to_f, SAME_PIN_METERS
                    )
                    .limit(SAME_PIN_CANDIDATE_LIMIT).to_a
        return if rows.size >= SAME_PIN_CANDIDATE_LIMIT

        candidates = rows.reject { |place| claimed_ids.include?(place.id) }
        candidates.first if candidates.size == 1
      end

      def adopt_rename(place, extracted)
        attributes = {
          geodata: (place.geodata || {}).merge('external_place_id' => extracted.external_place_id),
          updated_at: Time.current
        }
        attributes[:name] = place_name(extracted) unless place.name_locked?

        place.update_columns(attributes)
      rescue ActiveRecord::RecordNotUnique
        nil
      end

      def place_name(extracted)
        extracted.name.presence&.truncate(NAME_LIMIT) || 'Unknown'
      end

      def adopt_identity(place, extracted)
        return if extracted.external_place_id.blank?

        geodata = place.geodata || {}
        return if geodata['external_place_id'].present?

        place.update_columns(
          geodata: geodata.merge('external_place_id' => extracted.external_place_id),
          updated_at: Time.current
        )
      rescue ActiveRecord::RecordNotUnique
        nil
      end

      def attach_tag(place, extracted)
        return if extracted.tag_name.blank?

        tag = existing_tag(extracted.tag_name) || create_tag(extracted)
        return if tag.nil?
        return if tag.privacy_zone?

        place.add_tag(tag)
      end

      def existing_tag(name)
        key = name.downcase
        return tag_cache[key] if tag_cache.key?(key)

        tag_cache[key] = @user.tags.where('LOWER(tags.name) = ?', key).first
      end

      def tag_cache
        @tag_cache ||= {}
      end

      def create_tag(extracted)
        tag = @user.tags.create!(name: extracted.tag_name, color: extracted.tag_color)
        tag_cache[extracted.tag_name.downcase] = tag
      rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique
        tag_cache.delete(extracted.tag_name.downcase)
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
