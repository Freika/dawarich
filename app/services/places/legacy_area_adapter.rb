# frozen_string_literal: true

module Places
  # One-major-release compatibility adapter. Legacy Area IDs remain stable,
  # while every read and write is mirrored to the canonical Place.
  class LegacyAreaAdapter
    MATCH_RADIUS_METERS = 50

    def initialize(user:)
      @user = user
    end

    def resolve(area)
      ensure_owned!(area)
      mapped = LegacyAreaPlaceMapping.find_by(area_id: area.id)&.place
      return mapped if mapped

      Place.transaction do
        place = matching_places(area).one? ? matching_places(area).first : create_place(area)
        place.update!(visit_radius: [place.visit_radius, area.radius].max) if place.visit_radius < area.radius
        migrate_area_dependents(area, place)
        LegacyAreaPlaceMapping.create!(area:, place:)
        place
      end
    end

    def create(attributes)
      Area.transaction do
        area = user.areas.build(attributes)
        area.skip_visit_relabel = true
        area.save!
        place = create_place(area, skip_reattribution: false)
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
        place.update!(place_attributes(area))
      end

      place
    end

    def destroy(area)
      place = resolve(area)
      mapped_area_ids = LegacyAreaPlaceMapping.where(place_id: place.id).pluck(:area_id)

      Area.transaction do
        place.destroy!
        user.areas.where(id: mapped_area_ids).destroy_all
      end
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

    def matching_places(area)
      @matching_places ||= {}
      @matching_places[area.id] ||= user.places
                                        .where('LOWER(BTRIM(name)) = ?', area.name.to_s.strip.downcase)
                                        .near([area.latitude, area.longitude], MATCH_RADIUS_METERS, :m)
                                        .order(:id)
                                        .to_a
    end

    def create_place(area, skip_reattribution: true)
      place = user.places.build(place_attributes(area).merge(source: :manual))
      place.user_named = true
      place.skip_suggested_visit_reattribution = skip_reattribution
      place.save!
      place
    end

    def place_attributes(area)
      {
        name: area.name,
        latitude: area.latitude,
        longitude: area.longitude,
        visit_radius: area.radius
      }
    end

    def migrate_area_dependents(area, place)
      area.notes.order(:id).find_each do |note|
        existing = place.notes.find_by('CAST(noted_at AS date) = ?', note.noted_at.utc.to_date)
        if existing
          existing.update!(body: merge_text(existing.body, note.body), title: merge_text(existing.title, note.title))
          note.destroy!
        else
          note.update!(attachable: place)
        end
      end

      visits = user.visits.where(area_id: area.id)
      area_only = visits.where(place_id: nil)
      area_only.where(location_label: nil).update_all(location_label: area.name)
      area_only.update_all(place_id: place.id, area_id: nil)
      visits.where.not(place_id: nil).update_all(area_id: nil)
    end

    def merge_text(primary, secondary)
      [primary, secondary].compact_blank.uniq.join("\n\n").presence
    end
  end
end
