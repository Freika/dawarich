# frozen_string_literal: true

class PointSerializer
  EXCLUDED_ATTRIBUTES = %w[created_at updated_at visit_id id import_id user_id].freeze

  def initialize(point)
    @point = point
  end

  def call
    point.attributes.except(*EXCLUDED_ATTRIBUTES)
  end

  private

  attr_reader :point
end
