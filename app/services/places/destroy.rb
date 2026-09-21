# frozen_string_literal: true

module Places
  class Destroy
    def initialize(user:, place:)
      @user = user
      @place = place
    end

    def call
      raise ActiveRecord::RecordNotFound, 'Place not found' unless place.user_id == user.id

      Place.transaction do
        area_ids = LegacyAreaPlaceMapping.where(place_id: place.id).pluck(:area_id)
        user.areas.where(id: area_ids).find_each(&:destroy!)
        place.destroy!
      end
    end

    private

    attr_reader :user, :place
  end
end
