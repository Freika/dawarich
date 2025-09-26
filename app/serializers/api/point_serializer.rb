# frozen_string_literal: true

class Api::PointSerializer
  EXCLUDED_ATTRIBUTES = %w[
    created_at updated_at visit_id import_id user_id raw_data
    country_id
  ].freeze

  def initialize(point)
    @point = point
  end

  def call
    point.attributes.except(*EXCLUDED_ATTRIBUTES).tap do |attributes|
      lat = point.lat
      lon = point.lon

      attributes['latitude'] = lat.nil? ? nil : lat.to_s
      attributes['longitude'] = lon.nil? ? nil : lon.to_s
    end
  end

  private

  attr_reader :point
end
