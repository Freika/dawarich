# frozen_string_literal: true

class Shared::TripsController < ApplicationController
  before_action :authenticate_user!, except: [:show]
  before_action :authenticate_active_user!, only: [:update]

  def show
    @trip = Trip.find_by(sharing_uuid: params[:trip_uuid])

    unless @trip&.public_accessible?
      return redirect_to root_path,
                         alert: 'Shared trip not found or no longer available'
    end

    @user = @trip.user
    @is_public_view = true
    @coordinates = @trip.path.present? ? extract_coordinates : []
    @photo_previews = @trip.share_photos? ? fetch_photo_previews : []

    render 'trips/public_show'
  end

  def update
    @trip = current_user.trips.find(params[:id])

    return head :not_found unless @trip

    if params[:enabled] == '1'
      sharing_options = {
        expiration: params[:expiration] || '24h'
      }

      # Add optional sharing settings
      sharing_options[:share_notes] = params[:share_notes] == '1'
      sharing_options[:share_photos] = params[:share_photos] == '1'

      @trip.enable_sharing!(**sharing_options)
      sharing_url = shared_trip_url(@trip.sharing_uuid)

      render json: {
        success: true,
        sharing_url: sharing_url,
        message: 'Sharing enabled successfully'
      }
    else
      @trip.disable_sharing!

      render json: {
        success: true,
        message: 'Sharing disabled successfully'
      }
    end
  rescue StandardError => e
    render json: {
      success: false,
      message: 'Failed to update sharing settings',
      error: e.message
    }, status: :unprocessable_content
  end

  private

  def extract_coordinates
    return [] unless @trip.path&.coordinates

    # Convert PostGIS LineString coordinates [lng, lat] to [lat, lng] for Leaflet
    @trip.path.coordinates.map { |coord| [coord[1], coord[0]] }
  end

  def fetch_photo_previews
    Rails.cache.fetch("trip_photos_#{@trip.id}", expires_in: 1.day) do
      @trip.photo_previews
    end
  rescue StandardError => e
    Rails.logger.error("Failed to fetch photo previews for trip #{@trip.id}: #{e.message}")
    []
  end
end
