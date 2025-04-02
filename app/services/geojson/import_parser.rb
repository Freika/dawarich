# frozen_string_literal: true

class Geojson::ImportParser
  include Imports::Broadcaster
  include PointValidation

  attr_reader :import, :user_id

  def initialize(import, user_id)
    @import  = import
    @user_id = user_id
  end

  def call
    import.file.download do |file|
      json = Oj.load(file)

      data = Geojson::Params.new(json).call

      data.each.with_index(1) do |point, index|
        next if point_exists?(point, user_id)

        Point.create!(point.merge(user_id:, import_id: import.id))

        broadcast_import_progress(import, index)
      end
    end
  end
end
