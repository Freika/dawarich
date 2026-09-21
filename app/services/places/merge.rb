# frozen_string_literal: true

module Places
  class Merge
    class VisitConflict < StandardError
      attr_reader :conflicts

      def initialize(conflicts)
        @conflicts = conflicts
        super('Visits with the same start time prevent this Place merge')
      end
    end

    def initialize(user:, survivor:, duplicate:)
      @user = user
      @survivor = survivor
      @duplicate = duplicate
    end

    def call
      validate!

      Place.transaction do
        lock_places!
        merge_visits
        merge_suggestions
        merge_tags
        merge_timeline_notes
        merge_legacy_mappings

        merged_attributes = {
          note: merge_text(survivor.note, duplicate.note),
          geodata: duplicate.geodata.deep_merge(survivor.geodata)
        }

        duplicate.destroy!
        survivor.update!(merged_attributes)
      end

      survivor.reload
    end

    private

    attr_reader :user, :survivor, :duplicate

    def validate!
      raise ArgumentError, 'Places must be different' if survivor.id == duplicate.id
      return if survivor.user_id == user.id && duplicate.user_id == user.id

      raise ActiveRecord::RecordNotFound, 'Place not found'
    end

    def lock_places!
      Place.where(id: [survivor.id, duplicate.id]).order(:id).lock.load
    end

    def merge_visits
      conflicting = duplicate.visits.where(<<~SQL.squish, survivor.id)
        EXISTS (
          SELECT 1
          FROM visits survivor_visits
          WHERE survivor_visits.user_id = visits.user_id
            AND survivor_visits.started_at = visits.started_at
            AND survivor_visits.place_id = ?
        )
      SQL
      conflict_details = conflicting.order(:started_at).map do |visit|
        other = survivor.visits.find_by(user_id: visit.user_id, started_at: visit.started_at)
        { duplicate_id: visit.id, survivor_id: other.id, started_at: visit.started_at }
      end
      raise VisitConflict, conflict_details if conflict_details.any?

      duplicate.visits.update_all(place_id: survivor.id)
    end

    def merge_suggestions
      duplicate.place_visits.find_each do |suggestion|
        PlaceVisit.find_or_create_by!(visit_id: suggestion.visit_id, place_id: survivor.id)
      end
      duplicate.place_visits.delete_all
    end

    def merge_tags
      missing_tag_ids = duplicate.tag_ids - survivor.tag_ids
      survivor.tag_ids = survivor.tag_ids + missing_tag_ids if missing_tag_ids.any?
    end

    def merge_timeline_notes
      duplicate.notes.order(:id).find_each do |note|
        existing = survivor.notes.find_by('CAST(noted_at AS date) = ?', note.noted_at.utc.to_date)
        if existing
          existing.update!(
            title: merge_text(existing.title, note.title),
            body: merge_text(existing.body, note.body)
          )
          note.destroy!
        else
          note.update!(attachable: survivor)
        end
      end
    end

    def merge_legacy_mappings
      LegacyAreaPlaceMapping.where(place_id: duplicate.id).update_all(place_id: survivor.id)
    end

    def merge_text(primary, secondary)
      [primary, secondary].compact_blank.uniq.join("\n\n").presence
    end
  end
end
