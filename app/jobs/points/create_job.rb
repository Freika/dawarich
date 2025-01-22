# frozen_string_literal: true

class Points::CreateJob < ApplicationJob
  queue_as :default

  def perform(params, user_id)
    data = Points::Params.new(params, user_id).call

    data.each_slice(1000) do |location_batch|
      Point.upsert_all(
        location_batch,
        unique_by: %i[latitude longitude timestamp user_id],
        returning: false
      )
    end
  end
end
