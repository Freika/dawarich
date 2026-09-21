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
        promote_place(area, place)
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
      place.reattribute_suggested_visits_on_create = !skip_reattribution
      place.save!
      place
    end

    def promote_place(area, place)
      place.user_named = true
      place.skip_suggested_visit_reattribution = true
      place.update!(
        name: area.name,
        source: :manual,
        name_locked_at: place.name_locked_at || Time.current,
        visit_radius: [place.visit_radius, area.radius].max
      )
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
      occupied_started_at = user.visits.where(place_id: place.id, started_at: area_only.select(:started_at))
                                .pluck(:started_at).to_set

      area_only.order(:id).find_each do |visit|
        attributes = { area_id: nil, location_label: visit.location_label || area.name }
        unless occupied_started_at.include?(visit.started_at)
          attributes[:place_id] = place.id
          occupied_started_at << visit.started_at
        end
        visit.update_columns(attributes)
      end
      visits.where.not(place_id: nil).update_all(area_id: nil)
    end

    def merge_text(primary, secondary)
      [primary, secondary].compact_blank.uniq.join("\n\n").presence
    end
  end
end
