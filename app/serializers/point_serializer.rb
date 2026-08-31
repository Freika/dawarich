# frozen_string_literal: true

class PointSerializer
  EXCLUDED_ATTRIBUTES = %w[
    created_at updated_at visit_id id import_id user_id raw_data lonlat
    reverse_geocoded_at country_id altitude_decimal source_id
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
      # The device/importer combo reads through point_sources on stamped
      # rows: `attributes` alone would emit the raw legacy columns, which
      # the table rewrite drops. Re-assigning existing keys keeps the
      # payload's key order, so the output stays byte-identical.
      PointDimensionReads::DIMENSION_ATTRIBUTES.each do |attribute|
        attributes[attribute] = point.public_send(attribute)
      end
    end
  end

  private

  attr_reader :point
end
