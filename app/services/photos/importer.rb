# frozen_string_literal: true

class Photos::Importer
  include Imports::Broadcaster
  include PointValidation
  attr_reader :import, :user_id, :file_path

  def initialize(import, user_id, file_path = nil)
    @import = import
    @user_id = user_id
    @file_path = file_path
  end

  def call
    json = if file_path && File.exist?(file_path)
             Oj.load_file(file_path, mode: :compat)
           else
             file_content = Imports::SecureFileDownloader.new(import.file).download_with_verification
             Oj.load(file_content, mode: :compat)
           end

    json.each.with_index(1) { |point, index| create_point(point, index) }
  end

  def create_point(point, index)
    return 0 unless valid?(point)
    return 0 if point_exists?(point, point['timestamp'])

    Point.create(
      lonlat:    point['lonlat'],
      longitude: point['longitude'],
      latitude:  point['latitude'],
      timestamp: point['timestamp'].to_i,
      raw_data:  point,
      import_id: import.id,
      user_id:
    )

    broadcast_import_progress(import, index)
  end

  def valid?(point)
    point['latitude'].present? &&
      point['longitude'].present? &&
      point['timestamp'].present?
  end
end
