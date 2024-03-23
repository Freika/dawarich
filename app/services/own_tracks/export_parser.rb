# frozen_string_literal: true

class OwnTracks::ExportParser
  attr_reader :file_path, :file, :json, :import_id

  def initialize(file_path, import_id = nil)
    @file_path = file_path

    raise 'File not found' unless File.exist?(@file_path)

    @file = File.read(@file_path)
    @json = JSON.parse(@file)
    @import_id = import_id
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
        import_id: import_id
      )

      points += 1
    end

    doubles = points_data.size - points

    { raw_points: points_data.size, points: points, doubles: doubles }
  end

  private

  def parse_json
    points = []

    json.keys.each do |user|
      json[user].keys.each do |devise|
        json[user][devise].each { |point| points << OwnTracks::Params.new(point).call }
      end
    end

    points
  end
end
