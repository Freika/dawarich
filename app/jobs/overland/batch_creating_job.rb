# frozen_string_literal: true

class Overland::BatchCreatingJob < ApplicationJob
  queue_as :points

  def perform(params, user_id)
    Overland::PointsCreator.new(params, user_id).call
  end
end
