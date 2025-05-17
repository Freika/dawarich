# frozen_string_literal: true

class Geojson::Importer
  include Imports::Broadcaster
  include PointValidation

  attr_reader :import, :user_id

  def initialize(import, user_id)
    @import  = import
    @user_id = user_id
  end

  def call
    file_content = Imports::SecureFileDownloader.new(import.file).download_with_verification
    json = Oj.load(file_content)

    data = Geojson::Params.new(json).call

    data.each.with_index(1) do |point, index|
      next if point[:lonlat].nil?
      next if point_exists?(point, user_id)

      Point.create!(point.merge(user_id:, import_id: import.id))

      broadcast_import_progress(import, index)
    end
  end
end
