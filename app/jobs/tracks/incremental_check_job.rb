# frozen_string_literal: true

class Tracks::IncrementalCheckJob < ApplicationJob
  queue_as :tracks

  def perform(user_id, point_id)
    user = User.find(user_id)
    point = Point.find(point_id)

    Tracks::IncrementalProcessor.new(user, point).call
  end
end
