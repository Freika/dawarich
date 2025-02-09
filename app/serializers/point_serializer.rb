# frozen_string_literal: true

class PointSerializer
  EXCLUDED_ATTRIBUTES = %w[
    created_at updated_at visit_id id import_id user_id raw_data city_id
    country_id state_id county_id
  ].freeze

  def initialize(point)
    @point = point
  end

  def call
    attributes
  end

  private

  attr_reader :point

  def attributes
    attrs = point.attributes.except(*EXCLUDED_ATTRIBUTES)
    attrs[:city] = point.city_name
    attrs[:country] = point.country_name

    attrs
  end
end
