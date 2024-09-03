# frozen_string_literal: true

class Geojson::ImportParser
  attr_reader :import, :json, :user_id

  def initialize(import, user_id)
    @import  = import
    @json    = import.raw_data
    @user_id = user_id
  end

  def call
    data = Geojson::Params.new(json).call

    data.each do |point|
      next if point_exists?(point, user_id)

      Point.create!(point.merge(user_id:, import_id: import.id))
    end
  end

  private

  def point_exists?(params, user_id)
    Point.exists?(
      latitude:  params[:latitude],
      longitude: params[:longitude],
      timestamp: params[:timestamp],
      user_id:
    )
  end
end
