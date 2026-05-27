# frozen_string_literal: true

module Places
  module BulkInsertable
    extend ActiveSupport::Concern

    BATCH_SIZE = 500
    MAX_NAME_LENGTH = 255
    LATITUDE_RANGE = (-90.0..90.0)
    LONGITUDE_RANGE = (-180.0..180.0)

    private

    def place_row(name:, latitude:, longitude:, source:)
      lat = coordinate(latitude, LATITUDE_RANGE)
      lon = coordinate(longitude, LONGITUDE_RANGE)
      return if lat.nil? || lon.nil?
      return if Points::NullIsland.coordinates?(lon, lat)

      now = Time.current

      {
        name: place_name(name),
        latitude: lat,
        longitude: lon,
        lonlat: "POINT(#{lon} #{lat})",
        source: source,
        user_id: user_id,
        import_id: import.id,
        geodata: {},
        # The name came from the user's own file, so nightly reverse geocoding
        # must not rename it.
        name_locked_at: now,
        created_at: now,
        updated_at: now
      }
    end

    # Re-importing the same favourites file is routine — OsmAnd rewrites it on
    # every edit — so a place already recorded under this name and position is
    # re-claimed by the newer import rather than duplicated. The partial unique
    # index makes that hold across concurrent imports too, which a read-then-
    # write check cannot. Returns the number of rows this file accounted for,
    # whether freshly inserted or already present.
    def insert_places(rows)
      deduped = rows.uniq { |row| place_key(row) }
      return 0 if deduped.empty?

      Place.upsert_all(
        deduped,
        unique_by: :index_imported_places_uniqueness,
        update_only: %i[import_id],
        returning: Arel.sql('id')
      ).length
    end

    def place_key(row)
      [row[:name], row[:latitude], row[:longitude]]
    end

    def place_name(value)
      name = value.to_s.strip
      return default_place_name if name.blank?

      name.truncate(MAX_NAME_LENGTH)
    end

    # A file can carry junk where a number belongs; `to_f` would turn "north"
    # into a confident 0.0, so anything non-numeric or off-globe is dropped.
    def coordinate(value, range)
      return if value.blank?

      number = Float(value, exception: false)
      return if number.nil? || !range.cover?(number)

      number.round(6)
    end
  end
end
