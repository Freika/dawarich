# frozen_string_literal: true

class Photoprism::ImportGeodata
  attr_reader :user, :start_date, :end_date

  def initialize(user, start_date: '1970-01-01', end_date: nil)
    @user = user
    @start_date = start_date
    @end_date = end_date
  end

  def call
    photoprism_data = retrieve_photoprism_data

    log_no_data and return if photoprism_data.empty?

    photoprism_data_json = parse_photoprism_data(photoprism_data)
    file_name         = file_name(photoprism_data_json)
    import            = user.imports.find_or_initialize_by(name: file_name, source: :photoprism_api)

    create_import_failed_notification(import.name) and return unless import.new_record?

    import.raw_data = photoprism_data_json
    import.save!

    ImportJob.perform_later(user.id, import.id)
  end

  private

  def retrieve_photoprism_data
    Photoprism::RequestPhotos.new(user, start_date:, end_date:).call
  end

  def parse_photoprism_data(photoprism_data)
    geodata = photoprism_data.map do |asset|
      next unless valid?(asset)

      extract_geodata(asset)
    end

    geodata.compact.sort_by { |data| data[:timestamp] }
  end

  def valid?(asset)
    asset['Lat'] &&
      asset['Lat'] != 0 &&
      asset['Lng'] &&
      asset['Lng'] != 0 &&
      asset['TakenAt']
  end

  def extract_geodata(asset)
    {
      latitude: asset.dig('exifInfo', 'latitude'),
      longitude: asset.dig('exifInfo', 'longitude'),
      timestamp: Time.zone.parse(asset.dig('exifInfo', 'dateTimeOriginal')).to_i
    }
  end

  def log_no_data
    Rails.logger.info 'No geodata found for Photoprism'
  end

  def create_import_failed_notification(import_name)
    Notifications::Create.new(
      user:,
      kind: :info,
      title: 'Import was not created',
      content: "Import with the same name (#{import_name}) already exists. If you want to proceed, delete the existing import and try again."
    ).call
  end

  def file_name(photoprism_data_json)
    from              = Time.zone.at(photoprism_data_json.first[:timestamp]).to_date
    to                = Time.zone.at(photoprism_data_json.last[:timestamp]).to_date

    "photoprism-geodata-#{user.email}-from-#{from}-to-#{to}.json"
  end
end
