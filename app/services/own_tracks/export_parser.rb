# frozen_string_literal: true

class OwnTracks::ExportParser
  attr_reader :import, :data, :user_id

  def initialize(import, user_id)
    @import = import
    @data = import.raw_data
    @user_id = user_id
  end

  def call
    points_data = parse_data

    points_data.each do |point_data|
      next if Point.exists?(
        timestamp: point_data[:timestamp],
        latitude: point_data[:latitude],
        longitude: point_data[:longitude],
        user_id:
      )

      point = Point.new(point_data).tap do |p|
        p.user_id = user_id
        p.import_id = import.id
      end

      point.save
    end
  end

  private

  def parse_data
    data.split("\n").map do |line|
      OwnTracks::Params.new(
        JSON.parse(line.split("\t*                 \t")[1])
      ).call
    end
  end
end
