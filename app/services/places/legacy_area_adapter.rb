# frozen_string_literal: true

module Places
  # One-major-release compatibility adapter. Legacy Area IDs remain stable,
  # while every read and write is mirrored to the canonical Place.
  class LegacyAreaAdapter
    PLACE_FIELDS = { name: :name, latitude: :latitude, longitude: :longitude, radius: :visit_radius }.freeze

    def initialize(user:)
      @user = user
    end

    def resolve(area)
      ensure_owned!(area)
      mapped = LegacyAreaPlaceMapping.find_by(area_id: area.id)&.place
      return mapped if mapped

      AreasBackfill.new.migrate(area)
    rescue ActiveRecord::RecordNotUnique, ActiveRecord::RecordInvalid
      LegacyAreaPlaceMapping.find_by(area_id: area.id)&.place || raise
    end

    def create(attributes)
      Area.transaction do
        area = user.areas.build(attributes)
        area.skip_visit_relabel = true
        area.save!
        place = create_place(area)
        LegacyAreaPlaceMapping.create!(area:, place:)
        [area, place]
      end
    end

    def update(area, attributes)
      place = resolve(area)

      Area.transaction do
        area.skip_visit_relabel = true
        area.update!(attributes)
        place.user_named = true
        # Coordinates are the location data the user explicitly chose to persist.
        # codeql[rb/clear-text-storage-sensitive-data]
        place.update!(attributes.to_h.symbolize_keys.slice(*PLACE_FIELDS.keys).transform_keys(PLACE_FIELDS))
      end

      place
    end

    def destroy(area)
      place = resolve(area)
      Places::Destroy.new(user:, place:).call
    end

    def payload(area, place = resolve(area))
      {
        id: area.id,
        name: place.name,
        latitude: place.lat,
        longitude: place.lon,
        radius: place.visit_radius,
        user_id: user.id,
        created_at: place.created_at,
        updated_at: place.updated_at
      }
    end

    private

    attr_reader :user

    def ensure_owned!(area)
      raise ActiveRecord::RecordNotFound, 'Area not found' unless area.user_id == user.id
    end

    def create_place(area)
      place = user.places.build(place_attributes(area).merge(source: :manual))
      place.user_named = true
      place.reattribute_suggested_visits_on_create = true
      place.save!
      place
    end

    def place_attributes(area)
      {
        name: area.name,
        latitude: area.latitude,
        longitude: area.longitude,
        visit_radius: area.visit_radius
      }
    end
  end
end
