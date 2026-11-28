# frozen_string_literal: true

module Homes
  # Makes the user's Place at a point (reused, or created) an open-dated Home.
  # Calling it again for the same spot returns the same Home.
  class CreateAtLocation
    def initialize(user:, latitude:, longitude:)
      @user = user
      @latitude = latitude
      @longitude = longitude
    end

    def call
      ActiveRecord::Base.transaction do
        place = existing_place || create_place
        place.adopt!
        @user.homes.find_or_create_by!(place:, ended_on: nil)
      end
    end

    private

    def existing_place
      @user.places.attribution_for(@latitude, @longitude)
    end

    def create_place
      place = @user.places.new(
        latitude: @latitude, longitude: @longitude, source: :manual,
        name: I18n.t('trip_detection.home_place_name')
      )
      place.user_named = true
      place.save!
      place
    end
  end
end
