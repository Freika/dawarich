# frozen_string_literal: true

# Streams Google's Records.json and yields the deviceTag of each location.
#
# Records.json holds every device on the Google account in one file, so the
# deviceTag is the only thing separating a phone that travelled from a tablet
# left at home. The file runs to hundreds of megabytes, so it is read as a
# stream rather than parsed into memory.
#
# Only the location's own timestamp counts: each location also carries nested
# `activity` entries with timestamps of their own, and those must not be
# mistaken for a fix.
class GoogleMaps::RecordsDeviceTagStreamHandler < Oj::Saj
  LOCATIONS_KEY = 'locations'

  def initialize(&on_location)
    super()
    @on_location = on_location
    @in_locations = false
    @depth = 0
    reset_location
  end

  def array_start(key = nil, *_)
    @in_locations = true if @depth.zero? && normalize(key) == LOCATIONS_KEY
  end

  def array_end(key = nil, *_)
    @in_locations = false if normalize(key) == LOCATIONS_KEY && @depth.zero?
  end

  def hash_start(_key = nil, *_)
    return unless @in_locations

    @depth += 1
    reset_location if location_level?
  end

  def hash_end(_key = nil, *_)
    return unless @in_locations

    if location_level? && @timestamp && @device_tag
      @on_location.call(@timestamp, @device_tag, @latitude_e7, @longitude_e7)
    end
    @depth -= 1
  end

  def add_value(value, key = nil)
    return unless @in_locations && location_level?

    case normalize(key)
    when 'timestamp' then @timestamp = value
    when 'timestampMs' then @timestamp ||= value
    when 'deviceTag' then @device_tag = value
    when 'latitudeE7' then @latitude_e7 = value
    when 'longitudeE7' then @longitude_e7 = value
    end
  end

  private

  def reset_location
    @timestamp = nil
    @device_tag = nil
    @latitude_e7 = nil
    @longitude_e7 = nil
  end

  def location_level? = @depth == 1

  def normalize(key) = key.nil? ? nil : key.to_s
end
