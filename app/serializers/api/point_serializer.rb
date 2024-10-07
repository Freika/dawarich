# frozen_string_literal: true

class Api::PointSerializer < PointSerializer
  EXCLUDED_ATTRIBUTES = %w[created_at updated_at visit_id import_id user_id raw_data].freeze

  def call
    point.attributes.except(*EXCLUDED_ATTRIBUTES)
  end
end
