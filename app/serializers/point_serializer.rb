# frozen_string_literal: true

class PointSerializer
  EXCLUDED_ATTRIBUTES = %w[
    created_at updated_at visit_id id import_id user_id raw_data lonlat
    reverse_geocoded_at country_id altitude_decimal
  ].freeze

  def initialize(point)
    @point = point
  end

  def call
    point.attributes.except(*EXCLUDED_ATTRIBUTES).tap do |attributes|
      attributes['latitude'] = point.lat.to_s
      attributes['longitude'] = point.lon.to_s
      # Read through the model's override so we surface the precise
      # decimal value when `altitude_decimal` is populated, not the
      # truncated integer column.
      attributes['altitude'] = point.altitude
    end
  end

  private

  attr_reader :point
end
