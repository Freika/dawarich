# frozen_string_literal: true

class Api::PointSerializer
  EXCLUDED_ATTRIBUTES = %w[
    created_at updated_at visit_id import_id user_id raw_data
    country_id source_id
  ].freeze

  def initialize(point)
    @point = point
  end

  def call
    point.attributes.except(*EXCLUDED_ATTRIBUTES).tap do |attributes|
      lat = point.lat
      lon = point.lon

      attributes['latitude']  = lat&.to_s
      attributes['longitude'] = lon&.to_s
      attributes['country_name'] = point.country_name
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
