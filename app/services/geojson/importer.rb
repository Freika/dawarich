# frozen_string_literal: true

class Geojson::Importer
  include Imports::Broadcaster
  include PointValidation

  attr_reader :import, :user_id, :file_path

  def initialize(import, user_id, file_path = nil)
    @import  = import
    @user_id = user_id
    @file_path = file_path
  end

  def call
    json = load_json_data
    data = Geojson::Params.new(json).call

    data.each.with_index(1) do |point, index|
      next if point[:lonlat].nil?
      next if point_exists?(point, user_id)

      Point.create!(point.merge(user_id:, import_id: import.id))

      broadcast_import_progress(import, index)
    end
  end

  private

  def load_json_data
    if file_path && File.exist?(file_path)
      Oj.load_file(file_path, mode: :compat)
    else
      file_content = Imports::SecureFileDownloader.new(import.file).download_with_verification
      Oj.load(file_content, mode: :compat)
    end
  end
end
