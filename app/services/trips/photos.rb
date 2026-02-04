# frozen_string_literal: true

class Trips::Photos
  def initialize(trip, user)
    @trip = trip
    @user = user
  end

  def call
    return [] unless can_fetch_photos?

    photos
  end

  private

  attr_reader :trip, :user

  def can_fetch_photos?
    user.immich_integration_configured? ||
      user.photoprism_integration_configured? ||
      google_photos_configured?
  end

  def google_photos_configured?
    DawarichSettings.google_photos_available? && user.google_photos_integration_configured?
  end

  def photos
    return @photos if defined?(@photos)

    photos = Photos::Search.new(
      user,
      start_date: trip.started_at.to_date.to_s,
      end_date: trip.ended_at.to_date.to_s
    ).call

    @photos = photos.map { |photo| photo_thumbnail(photo) }
  end

  def photo_thumbnail(asset)
    {
      id: asset[:id],
      url: "/api/v1/photos/#{asset[:id]}/thumbnail.jpg?api_key=#{user.api_key}&source=#{asset[:source]}",
      source: asset[:source],
      orientation: asset[:orientation]
    }
  end
end
