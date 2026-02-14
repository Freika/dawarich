# frozen_string_literal: true

class Photos::Search
  attr_reader :user, :start_date, :end_date, :errors

  def initialize(user, start_date: '1970-01-01', end_date: nil)
    @user = user
    @start_date = start_date
    @end_date = end_date
    @errors = []
  end

  def call
    photos = []

    immich_photos = request_immich if user.immich_integration_configured?
    photoprism_photos = request_photoprism if user.photoprism_integration_configured?
    google_photos = request_google_photos if google_photos_available?

    photos << immich_photos if immich_photos.present?
    photos << photoprism_photos if photoprism_photos.present?
    photos << google_photos if google_photos.present?

    photos.flatten.map { |photo| Api::PhotoSerializer.new(photo, photo[:source]).call }
  end

  private

  def request_immich
    assets = Immich::RequestPhotos.new(
      user,
      start_date: start_date,
      end_date: end_date
    ).call
    if assets.nil?
      errors << :immich
      return nil
    end

    assets.map { |asset| transform_asset(asset, 'immich') }.compact
  end

  def request_photoprism
    Photoprism::RequestPhotos.new(
      user,
      start_date: start_date,
      end_date: end_date
    ).call.map { |asset| transform_asset(asset, 'photoprism') }.compact
  end

  def transform_asset(asset, source)
    asset_type = asset['type'] || asset['Type']
    return if asset_type&.downcase == 'video'

    asset.merge(source: source)
  end

  def google_photos_available?
    DawarichSettings.google_photos_available? && user.google_photos_integration_configured?
  end

  def request_google_photos
    assets = GooglePhotos::RequestPhotos.new(
      user,
      start_date: start_date,
      end_date: end_date
    ).call

    if assets.nil?
      errors << :google_photos
      return nil
    end

    assets.map { |asset| transform_google_photos_asset(asset) }.compact
  end

  def transform_google_photos_asset(asset)
    # Google Photos only returns photos (we filter for PHOTO type in the API request)
    asset.merge(source: 'google_photos')
  end
end
