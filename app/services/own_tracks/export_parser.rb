# frozen_string_literal: true

class OwnTracks::ExportParser
  attr_reader :import, :json

  def initialize(import)
    @import = import
    @json = import.raw_data
  end

  def call
    points_data = parse_json

    points = 0

    points_data.each do |point_data|
      next if Point.exists?(timestamp: point_data[:timestamp], tracker_id: point_data[:tracker_id])

      Point.create(
        latitude: point_data[:latitude],
        longitude: point_data[:longitude],
        timestamp: point_data[:timestamp],
        raw_data: point_data[:raw_data],
        topic: point_data[:topic],
        tracker_id: point_data[:tracker_id],
        import_id: import.id
      )

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
