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
      # velocity stayed a string on the wire when the column went numeric:
      # three mobile HTTP stacks decode this payload.
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
