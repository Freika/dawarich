# frozen_string_literal: true

module Places
  class DeleteIfOrphan
    def self.call(place_id)
      new(place_id).call
    end

    def initialize(place_id)
      @place_id = place_id
    end

    def call
      place = Place.find_by(id: @place_id)
      return false unless place
      return false unless place.photon?
      return false if place.note.present?
      return false if Visit.active.where(place_id: @place_id).exists?
      return false if Tagging.where(taggable_id: @place_id, taggable_type: 'Place').exists?

      Place.transaction do
        # Only hidden visits (tombstones/declines) can still reference the
        # place here; detach them so the FK allows the delete. Their dedup
        # role survives — Visit#center falls back to the visit's own points.
        Visit.where(place_id: @place_id).update_all(place_id: nil)
        PlaceVisit.where(place_id: @place_id).delete_all
        place.delete
      end
      true
    rescue ActiveRecord::InvalidForeignKey => e
      Rails.logger.warn("[DeleteIfOrphan] place=#{@place_id} FK race: #{e.message}")
      false
    end
  end
end
