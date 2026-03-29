# frozen_string_literal: true

class Immich::EnrichScan
  attr_reader :user, :start_date, :end_date, :tolerance

  DEFAULT_TOLERANCE = 1800 # 30 minutes in seconds

  def initialize(user, start_date: nil, end_date: nil, tolerance: DEFAULT_TOLERANCE)
    @user = user
    @start_date = start_date
    @end_date = end_date
    @tolerance = tolerance.to_i
  end

  def call
    return error_result('Immich URL is missing') if user.safe_settings.immich_url.blank?
    return error_result('Immich API key is missing') if user.safe_settings.immich_api_key.blank?

    immich_data = fetch_immich_photos
    return error_result(immich_data[:error]) if immich_data[:error]

    photos_without_geodata = filter_photos_without_geodata(immich_data[:photos])
    matches = match_photos_to_points(photos_without_geodata)

    {
      matches: matches,
      total_without_geodata: photos_without_geodata.size,
      total_matched: matches.size
    }
  end

  private

  def fetch_immich_photos
    photos = Immich::RequestPhotos.new(user, start_date: start_date || '1970-01-01', end_date:).call
    return { error: 'Failed to fetch photos from Immich' } if photos.nil?

    { photos: photos }
  end

  def filter_photos_without_geodata(photos)
    photos.reject { |photo| geodata?(photo) }
  end

  def geodata?(photo)
    lat = photo.dig('exifInfo', 'latitude')
    lon = photo.dig('exifInfo', 'longitude')

    lat.present? && lat != 0 && lon.present? && lon != 0
  end

  def match_photos_to_points(photos)
    return [] if photos.empty?

    # Load all relevant points in one query for batch optimization
    timestamps = photos.map { |p| parse_photo_timestamp(p) }.compact
    return [] if timestamps.empty?

    min_ts = timestamps.min - tolerance
    max_ts = timestamps.max + tolerance

    points = user.points
                 .where(timestamp: min_ts..max_ts)
                 .where.not(lonlat: nil)
                 .order(:timestamp)
                 .to_a

    return [] if points.empty?

    photos.filter_map { |photo| match_single_photo(photo, points) }
  end

  def match_single_photo(photo, sorted_points)
    photo_ts = parse_photo_timestamp(photo)
    return nil unless photo_ts

    # Binary search for insertion point
    idx = sorted_points.bsearch_index { |p| p.timestamp > photo_ts } || sorted_points.length

    before_point = idx.positive? ? sorted_points[idx - 1] : nil
    after_point = idx < sorted_points.length ? sorted_points[idx] : nil

    # Try interpolation first
    if before_point && after_point
      gap = after_point.timestamp - before_point.timestamp
      if gap <= tolerance &&
         (photo_ts - before_point.timestamp) <= tolerance &&
         (after_point.timestamp - photo_ts) <= tolerance
        return build_interpolated_match(photo, photo_ts, before_point, after_point)
      end
    end

    # Fall back to nearest point within tolerance
    nearest = find_nearest_within_tolerance(photo_ts, before_point, after_point)
    return nil unless nearest

    build_nearest_match(photo, photo_ts, nearest)
  end

  def find_nearest_within_tolerance(photo_ts, before_point, after_point)
    candidates = []
    candidates << before_point if before_point && (photo_ts - before_point.timestamp).abs <= tolerance
    candidates << after_point if after_point && (after_point.timestamp - photo_ts).abs <= tolerance

    candidates.min_by { |p| (p.timestamp - photo_ts).abs }
  end

  def build_interpolated_match(photo, photo_ts, before_point, after_point)
    gap = after_point.timestamp - before_point.timestamp
    fraction = (photo_ts - before_point.timestamp).to_f / gap

    lat = before_point.lat + (after_point.lat - before_point.lat) * fraction
    lon = before_point.lon + (after_point.lon - before_point.lon) * fraction

    nearest_ts = fraction <= 0.5 ? before_point.timestamp : after_point.timestamp

    build_match(photo, photo_ts, lat, lon, (photo_ts - nearest_ts).abs, 'interpolated')
  end

  def build_nearest_match(photo, photo_ts, point)
    build_match(photo, photo_ts, point.lat, point.lon, (photo_ts - point.timestamp).abs, 'nearest')
  end

  def build_match(photo, photo_ts, lat, lon, time_delta, method)
    {
      immich_asset_id: photo['id'],
      filename: photo['originalFileName'],
      photo_timestamp: Time.at(photo_ts).utc.iso8601,
      time_delta_seconds: time_delta,
      latitude: lat.round(6),
      longitude: lon.round(6),
      match_method: method
    }
  end

  def parse_photo_timestamp(photo)
    time_str = photo.dig('exifInfo', 'dateTimeOriginal') || photo['localDateTime']
    return nil if time_str.blank?

    Time.parse(time_str).utc.to_i
  rescue ArgumentError
    nil
  end

  def error_result(message)
    { error: message, matches: [], total_without_geodata: 0, total_matched: 0 }
  end
end
