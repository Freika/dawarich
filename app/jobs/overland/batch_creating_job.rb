# frozen_string_literal: true

class Overland::BatchCreatingJob < ApplicationJob
  queue_as :default

  def perform(params, user_id)
    data = Overland::Params.new(params).call

    records = data.map do |location|
      {
        lonlat: location[:lonlat],
        timestamp: location[:timestamp],
        user_id: user_id,
        created_at: Time.current,
        updated_at: Time.current
      }
    end

    # rubocop:disable Rails/SkipsModelValidations
    Point.upsert_all(
      records,
      unique_by: %i[lonlat timestamp user_id],
      returning: false,
      on_duplicate: :skip
    )
    # rubocop:enable Rails/SkipsModelValidations
  end
end
