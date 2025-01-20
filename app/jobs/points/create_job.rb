# frozen_string_literal: true

class Points::CreateJob < ApplicationJob
  queue_as :default

  def perform(params, user_id)
    data = Points::Params.new(params, user_id).call

    data.each_slice(1000) do |location_batch|
      Point.upsert_all(
        location_batch,
        unique_by: %i[latitude longitude timestamp user_id]
      )
    end
  end

  private

  def point_exists?(params, user_id)
    Point.exists?(
      latitude: params[:latitude],
      longitude: params[:longitude],
      timestamp: params[:timestamp],
      user_id:
    )
  end
end
