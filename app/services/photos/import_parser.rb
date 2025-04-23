# frozen_string_literal: true

class Photos::ImportParser
  include Imports::Broadcaster
  include PointValidation
  attr_reader :import, :user_id

  def initialize(import, user_id)
    @import = import
    @user_id = user_id
  end

  def call
    file_content = Imports::SecureFileDownloader.new(import.file).download_with_verification
    json = Oj.load(file_content)

    json.each.with_index(1) { |point, index| create_point(point, index) }
  end

  def create_point(point, index)
    return 0 if point['latitude'].blank? || point['longitude'].blank? || point['timestamp'].blank?
    return 0 if point_exists?(point, point['timestamp'])

    Point.create(
      lonlat: "POINT(#{point['longitude']} #{point['latitude']})",
      timestamp:  point['timestamp'],
      raw_data:   point,
      import_id:  import.id,
      user_id:
    )

    broadcast_import_progress(import, index)
  end
end
