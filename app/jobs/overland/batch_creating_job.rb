# frozen_string_literal: true

class Overland::BatchCreatingJob < ApplicationJob
  queue_as :default

  def perform(params, user_id)
    data = Overland::Params.new(params).call

    data.each do |location|
      Point.create!(location.merge(user_id:))
    end
  end
end
