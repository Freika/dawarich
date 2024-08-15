# frozen_string_literal: true

class OwnTracks::ExportParser
  attr_reader :import, :json, :user_id

  def initialize(import, user_id)
    @import = import
    @json = import.raw_data
    @user_id = user_id
  end

  def call
    points_data = parse_json

    points = 0

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

      points += 1
    end

    doubles = points_data.size - points
    processed = points + doubles

    { raw_points: points_data.size, points:, doubles:, processed: }
  end

  private

  def parse_json
    points = []

    json.each_key do |user|
      json[user].each_key do |devise|
        json[user][devise].each { |point| points << OwnTracks::Params.new(point).call }
      end
    end

    points
  end
end
