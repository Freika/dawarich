# frozen_string_literal: true

class OwnTracks::ExportParser
  include Imports::Broadcaster

  attr_reader :import, :data, :user_id

  def initialize(import, user_id)
    @import = import
    @data = import.raw_data
    @user_id = user_id
  end

  def call
    points_data = data.map { |point| OwnTracks::Params.new(point).call }

    points_data.each.with_index(1) do |point_data, index|
      next if Point.exists?(
        lonlat: point_data[:lonlat],
        timestamp: point_data[:timestamp],
        user_id:
      )

      point = Point.new(point_data).tap do |p|
        p.user_id = user_id
        p.import_id = import.id
      end

      point.save

      broadcast_import_progress(import, index)
    end
  end
end
