# frozen_string_literal: true

class Overland::BatchCreatingJob < ApplicationJob
  include PointValidation

  queue_as :default

  def perform(params, user_id)
    data = Overland::Params.new(params).call

    data.each do |location|
      next if point_exists?(location, user_id)

      Point.create!(location.merge(user_id:))
    end
  end
end
