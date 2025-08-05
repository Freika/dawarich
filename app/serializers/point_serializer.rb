# frozen_string_literal: true

class PointSerializer
  EXCLUDED_ATTRIBUTES = %w[
    created_at updated_at visit_id id import_id user_id raw_data lonlat
    reverse_geocoded_at country_id device_id
  ].freeze

  def initialize(point)
    @point = point
  end

  def call
    point.attributes.except(*EXCLUDED_ATTRIBUTES).tap do |attributes|
      attributes['latitude'] = point.lat.to_s
      attributes['longitude'] = point.lon.to_s
    end
  end

  private

  attr_reader :point
end
