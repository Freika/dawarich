class Overland::BatchCreatingJob < ApplicationJob
  queue_as :default

  def perform(params)
    data = Overland::Params.new(params).call

    data.each do |location|
      Point.create!(location)
    end
  end
end
