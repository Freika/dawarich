# frozen_string_literal: true

# Creates a Home at a point the user picked, from the onboarding modal.
class HomesController < ApplicationController
  include FlashStreamable

  before_action :authenticate_user!

  def create
    # Onboarding adds a first Home only; later periods are edited on the Place page.
    if current_user.homes.exists?
      return render turbo_stream: stream_flash(:notice, I18n.t('trip_detection.onboarding.home_exists'))
    end

    latitude = coordinate(:latitude, 90)
    longitude = coordinate(:longitude, 180)

    if latitude.nil? || longitude.nil?
      return render turbo_stream: stream_flash(:error, I18n.t('trip_detection.onboarding.invalid_location')),
                    status: :unprocessable_content
    end

    Homes::CreateAtLocation.new(user: current_user, latitude:, longitude:).call
    render turbo_stream: stream_flash(:success, I18n.t('trip_detection.onboarding.home_saved'))
  end

  private

  def coordinate(key, limit)
    value = Float(params[key], exception: false)
    value if value&.between?(-limit, limit)
  end
end
