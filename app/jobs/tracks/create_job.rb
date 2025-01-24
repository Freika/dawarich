# frozen_string_literal: true

class Tracks::CreateJob < ApplicationJob
  queue_as :default

  def perform(user_id, points_ids)
    coordinates =
      Point
      .where(user_id: user_id, id: points_ids)
      .order(timestamp: :asc)
      .pluck(:latitude, :longitude, :timestamp)

    path = Tracks::BuildPath.new(coordinates.map { |c| [c[0], c[1]] }).call

    Track.create!(
      user_id: user_id,
      started_at: Time.zone.at(coordinates.first.last),
      ended_at: Time.zone.at(coordinates.last.last),
      path: path
    )
  end
end
