# frozen_string_literal: true

class Photos::Search
  attr_reader :user, :start_date, :end_date, :tag_ids, :album_id, :errors

  def self.cached(user, start_date: '1970-01-01', end_date: nil, tag_ids: nil, album_id: nil, expires_in: 1.minute)
    normalized_tag_ids = Array(tag_ids).compact_blank.sort
    tag_fingerprint = normalized_tag_ids.presence&.join('-') || 'all'
    album_fingerprint = album_id.to_s.presence || 'all'
    key = "photos_search/#{user.id}/#{start_date}/#{end_date}/#{tag_fingerprint}/#{album_fingerprint}"

    cached = Rails.cache.read(key)
    return cached if cached.present?

    result = new(
      user,
      start_date: start_date,
      end_date: end_date,
      tag_ids: tag_ids,
      album_id: album_id
    ).call

    Rails.cache.write(key, result, expires_in: expires_in) if result.present?
    result
  end

  def initialize(user, start_date: '1970-01-01', end_date: nil, tag_ids: nil, album_id: nil)
    @user = user
    @start_date = start_date
    @end_date = end_date
    @tag_ids = tag_ids.nil? ? nil : Array(tag_ids).compact_blank
    @album_id = album_id.to_s.presence
    @errors = []
  end

  def call
    photos = []

    immich_photos = request_immich if user.immich_integration_configured?

    # Immich tag IDs cannot be applied to PhotoPrism. A tag-scoped search
    # therefore returns only matching Immich assets and never unfiltered
    # PhotoPrism assets.
    photoprism_photos =
      request_photoprism if tag_ids.nil? && album_id.nil? && user.photoprism_integration_configured?

    photos << immich_photos if immich_photos.present?
    photos << photoprism_photos if photoprism_photos.present?

    photos.flatten.map { |photo| Api::PhotoSerializer.new(photo, photo[:source]).call }
  end

  private

  def request_immich
    assets =
      if tag_ids.present? && tag_ids.many?
        request_immich_for_multiple_tags
      else
        request_immich_assets(tag_ids)
      end

    if assets.nil?
      errors << :immich
      return nil
    end

    assets
      .uniq { |asset| asset['id'] || asset[:id] }
      .map { |asset| transform_asset(asset, 'immich') }
      .compact
  end

  def request_immich_for_multiple_tags
    tag_ids.each_with_object([]) do |tag_id, assets|
      tagged_assets = request_immich_assets([tag_id])
      return nil if tagged_assets.nil?

      assets.concat(tagged_assets)
    end
  end

  def request_immich_assets(request_tag_ids)
    Immich::RequestPhotos.new(
      user,
      start_date: start_date,
      end_date: end_date,
      tag_ids: request_tag_ids,
      album_id: album_id
    ).call
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
