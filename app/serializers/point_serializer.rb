# frozen_string_literal: true

class PointSerializer
  EXCLUDED_ATTRIBUTES = %w[
    created_at updated_at visit_id id import_id user_id raw_data lonlat
    reverse_geocoded_at country_id source_id
  ].freeze

  def initialize(point)
    @point = point
  end

  def call
    point.attributes.except(*EXCLUDED_ATTRIBUTES).tap do |attributes|
      attributes['latitude'] = point.lat.to_s
      attributes['longitude'] = point.lon.to_s
      attributes['altitude'] = point.altitude
      # The scratch map reads properties.country_name; the key is computed
      # through the countries table since the column was dropped.
      attributes['country_name'] = point.country_name
      # velocity stayed a string on the wire when the column went numeric.
      attributes['velocity'] = point.velocity&.to_s
      # The device/importer combo lives on point_sources; `attributes` alone
      # no longer carries these keys at all.
      PointDimensionReads::DIMENSION_ATTRIBUTES.each do |attribute|
        attributes[attribute] = point.public_send(attribute)
      end
    end
  end

  private

  attr_reader :point
end
