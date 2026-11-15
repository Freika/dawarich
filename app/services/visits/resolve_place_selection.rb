# frozen_string_literal: true

module Visits
  # Validates a request's place_id / area_id and replaces a legacy area with
  # its place. Pass the visit on edits: its suggested places are selectable too.
  class ResolvePlaceSelection
    class Invalid < StandardError
      attr_reader :reason

      def initialize(reason)
        @reason = reason
        super(reason.to_s)
      end
    end

    def initialize(user, visit: nil)
      @user = user
      @visit = visit
    end

    def call(attributes)
      place_id, area_id = attributes.values_at(:place_id, :area_id)
      raise Invalid, :conflicting_place_and_area if place_id.present? && area_id.present?
      return attributes.merge(place_id: place_for_area(area_id).id, area_id: nil) if area_id.present?
      return attributes if place_id.blank?

      raise Invalid, :invalid_place if @visit && !selectable_place?(place_id)

      attributes.merge(area_id: nil)
    end

    private

    def place_for_area(area_id)
      area = @user.areas.find_by(id: area_id)
      raise Invalid, :invalid_area unless area

      Places::LegacyAreaAdapter.new(user: @user).resolve(area)
    end

    def selectable_place?(place_id)
      @user.places.exists?(place_id) || @visit.suggested_places.exists?(place_id)
    end
  end
end
