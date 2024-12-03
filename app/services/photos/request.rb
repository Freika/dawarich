# frozen_string_literal: true

class Photos::Request
  attr_reader :user, :start_date, :end_date

  def initialize(user, start_date: '1970-01-01', end_date: nil)
    @user = user
    @start_date = start_date
    @end_date = end_date
  end

  def call
    photos = []

    photos << request_immich if user.immich_integration_configured?
    photos << request_photoprism if user.photoprism_integration_configured?

    photos.flatten.map { |photo| Api::PhotoSerializer.new(photo, photo[:source]).call }
  end

  private

  def request_immich
    Immich::RequestPhotos.new(
      user,
      start_date: start_date,
      end_date: end_date
    ).call.map { |asset| transform_asset(asset, 'immich') }.compact
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
    return if asset_type.downcase == 'video'

    asset.merge(source: source)
  end
end
