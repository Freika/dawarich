# frozen_string_literal: true

module Places
  class AreasBackfill
    MATCH_RADIUS_METERS = 50
    BATCH_SIZE = 500

    attr_reader :report

    def initialize(batch_size: BATCH_SIZE, logger: Rails.logger)
      @batch_size = batch_size
      @logger = logger
      @report = Hash.new(0)
      @report[:ambiguous_area_ids] = []
      @report[:failed_area_ids] = []
      @report[:conflicting_visit_ids] = []
    end

    def call
      migration_error = migrate_areas
      migrate_visit_labels
      migrate_visit_associations

      logger.info("[#{self.class}] #{report.to_json}")
      raise migration_error if migration_error

      report
    end

    private

    attr_reader :batch_size, :logger

    def migrate_areas
      first_error = nil

      Area.where.not(id: LegacyAreaPlaceMapping.select(:area_id)).find_each(batch_size: batch_size) do |area|
        report[:areas_scanned] += 1
        migrate_area(area)
      rescue StandardError => e
        report[:areas_failed] += 1
        report[:failed_area_ids] << area.id
        logger.error("[#{self.class}] area_id=#{area.id} #{e.class}: #{e.message}")
        first_error ||= e
      end

      first_error
    end

    def migrate_area(area)
      candidates = matching_places(area)
      if candidates.many?
        report[:areas_ambiguous] += 1
        report[:ambiguous_area_ids] << area.id
        candidates = []
      end

      Place.transaction do
        place = candidates.first
        place = nil if place && note_dates_overlap?(area, place)

        if place
          promote_place(area, place)
          report[:areas_mapped] += 1
        else
          place = create_place(area)
          report[:places_created] += 1
        end

        move_notes(area, place)
        LegacyAreaPlaceMapping.create!(area: area, place: place)
      end
    end

    def matching_places(area)
      area.user.places
          .where('LOWER(BTRIM(name)) = ?', normalize(area.name))
          .near([area.latitude, area.longitude], MATCH_RADIUS_METERS, :m)
          .order(:id)
          .to_a
    end

    def normalize(name)
      name.to_s.strip.downcase
    end

    # Moving two different notes onto the same Place/date would create a state
    # the Note model refuses to save later. Keep a separate Place instead of
    # dropping or combining user text during an automatic migration.
    def note_dates_overlap?(area, place)
      area_dates = area.notes.pluck(:noted_at).compact.map { |time| time.utc.to_date }
      return false if area_dates.empty?

      place.notes.where('CAST(noted_at AS date) IN (?)', area_dates).exists?
    end

    def create_place(area)
      place = area.user.places.build(
        name: area.name,
        latitude: area.latitude,
        longitude: area.longitude,
        visit_radius: area.radius,
        source: :manual
      )
      place.user_named = true
      place.skip_suggested_visit_reattribution = true
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

    def move_notes(area, place)
      moved = area.notes.update_all(attachable_type: 'Place', attachable_id: place.id)
      report[:notes_moved] += moved
    end

    def migrate_visit_labels
      Visit.where(location_label: nil).where.not(name: nil).in_batches(of: batch_size) do |batch|
        report[:visit_labels_copied] += batch.update_all('location_label = name')
      end

      Visit.machine_detected.where.not(name: nil).in_batches(of: batch_size) do |batch|
        report[:suggested_visit_names_cleared] += batch.update_all(name: nil)
      end
    end

    def migrate_visit_associations
      LegacyAreaPlaceMapping.includes(:area, :place).find_each(batch_size: batch_size) do |mapping|
        Visit.where(area_id: mapping.area_id).find_each(batch_size: batch_size) do |visit|
          migrate_visit_association(visit, mapping)
        end
      end
    end

    def migrate_visit_association(visit, mapping)
      if visit.place_id.nil?
        if place_conflict?(visit, mapping.place_id)
          visit.update_columns(area_id: nil)
          record_visit_conflict(visit)
        else
          visit.update_columns(place_id: mapping.place_id, area_id: nil)
          report[:area_only_visits_reassigned] += 1
        end
      elsif visit.user.visits.machine_detected.exists?(id: visit.id)
        selected = select_place_for(visit, fallback: mapping.place)
        if place_conflict?(visit, selected.id)
          visit.update_columns(area_id: nil)
          record_visit_conflict(visit)
        else
          visit.update_columns(place_id: selected.id, area_id: nil)
          report[:dual_suggested_visits_reattributed] += 1
        end
      else
        visit.update_columns(area_id: nil)
        report[:dual_user_owned_visits_retained] += 1
      end
    end

    def place_conflict?(visit, place_id)
      visit.user.visits.where(place_id: place_id, started_at: visit.started_at).where.not(id: visit.id).exists?
    end

    def record_visit_conflict(visit)
      report[:visit_place_conflicts] += 1
      report[:conflicting_visit_ids] << visit.id
    end

    def select_place_for(visit, fallback:)
      center = visit_center(visit)
      return fallback unless center

      candidates = visit.user.places.containing(*center).to_a
      return fallback if candidates.empty?

      candidates.min_by do |place|
        [place.visit_radius, distance_meters(center, [place.lat, place.lon]), place.id]
      end
    end

    def visit_center(visit)
      coordinates = visit.points.pluck(
        Arel.sql('ST_Y(lonlat::geometry)'),
        Arel.sql('ST_X(lonlat::geometry)')
      )
      return fallback_center(visit) if coordinates.empty?

      count = coordinates.length.to_f
      [coordinates.sum { |lat, _lon| lat.to_f } / count,
       coordinates.sum { |_lat, lon| lon.to_f } / count]
    end

    def fallback_center(visit)
      return [visit.place.lat, visit.place.lon] if visit.place
      return [visit.area.lat, visit.area.lon] if visit.area

      nil
    end

    def distance_meters(first, second)
      Geocoder::Calculations.distance_between(first, second, units: :km) * 1000
    end
  end
end
