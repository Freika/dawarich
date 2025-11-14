# frozen_string_literal: true

class Shared::TripsController < ApplicationController
  def show
    @trip = Trip.find_by(sharing_uuid: params[:trip_uuid])

    redirect_to root_path, alert: 'Shared trip not found or no longer available' and return unless @trip&.public_accessible?

    @user = @trip.user
    @coordinates = extract_coordinates
    @photo_previews = fetch_photo_previews
  end

  private

  def extract_coordinates
    return [] unless @trip.path&.coordinates

    # Convert PostGIS LineString coordinates [lng, lat] to [lat, lng] for Leaflet
    @trip.path.coordinates.map { |coord| [coord[1], coord[0]] }
  end

  def fetch_photo_previews
    return [] unless @trip.share_photos?

    Rails.cache.fetch("trip_photos_#{@trip.id}", expires_in: 1.day) do
      @trip.photo_previews
    end
  rescue StandardError => e
    Rails.logger.error("Failed to fetch photo previews for trip #{@trip.id}: #{e.message}")
    []
  end
end
