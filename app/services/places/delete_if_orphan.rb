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
      return false unless Place.orphaned.exists?(@place_id)

      Place.delete_orphans([@place_id])
      true
    rescue ActiveRecord::InvalidForeignKey => e
      Rails.logger.warn("[DeleteIfOrphan] place=#{@place_id} FK race: #{e.message}")
      false
    end
  end
end
