# frozen_string_literal: true

module GooglePhotos
  class ImportGeodata
    attr_reader :user, :start_date, :end_date

    def initialize(user, start_date: '1970-01-01', end_date: nil)
      @user = user
      @start_date = start_date
      @end_date = end_date
    end

    def call
      photos_data = retrieve_google_photos_data

      return log_no_data if photos_data.blank?

      geodata_json = parse_photos_data(photos_data)
      return log_no_geodata if geodata_json.blank?

      file_name = generate_file_name(geodata_json)
      import = user.imports.find_or_initialize_by(name: file_name, source: :google_photos_api)

      create_import_failed_notification(import.name) and return unless import.new_record?

      import.file.attach(
        io: StringIO.new(geodata_json.to_json),
        filename: file_name,
        content_type: 'application/json'
      )

      import.save!
    end

    private

    def retrieve_google_photos_data
      GooglePhotos::RequestPhotos.new(user, start_date: start_date, end_date: end_date).call
    end

    def parse_photos_data(photos_data)
      geodata = photos_data.filter_map do |photo|
        next unless valid?(photo)

        extract_geodata(photo)
      end

      geodata.sort_by { |data| data[:timestamp] }
    end

    def valid?(photo)
      metadata = photo['mediaMetadata']
      return false unless metadata

      # Google Photos API doesn't always include location in the metadata response
      # Location data is only available if the photo has GPS coordinates embedded
      # We need to check for the presence of location data in the response
      # Note: Google Photos Library API has limited location access
      latitude = photo.dig('mediaMetadata', 'location', 'latitude')
      longitude = photo.dig('mediaMetadata', 'location', 'longitude')
      creation_time = metadata['creationTime']

      latitude.present? && longitude.present? && creation_time.present?
    end

    def extract_geodata(photo)
      location = photo.dig('mediaMetadata', 'location')
      latitude = location['latitude']
      longitude = location['longitude']
      creation_time = photo.dig('mediaMetadata', 'creationTime')

      {
        latitude: latitude,
        longitude: longitude,
        lonlat: "SRID=4326;POINT(#{longitude} #{latitude})",
        timestamp: Time.iso8601(creation_time).utc.to_i
      }
    end

    def log_no_data
      Rails.logger.info 'No data found from Google Photos'
    end

    def log_no_geodata
      Rails.logger.info 'No geodata found in Google Photos (photos may not have location data)'
    end

    def create_import_failed_notification(import_name)
      Notifications::Create.new(
        user: user,
        kind: :info,
        title: 'Import was not created',
        content: "Import with the same name (#{import_name}) already exists. " \
                 'If you want to proceed, delete the existing import and try again.'
      ).call
    end

    def generate_file_name(geodata_json)
      from = Time.zone.at(geodata_json.first[:timestamp]).to_date
      to = Time.zone.at(geodata_json.last[:timestamp]).to_date

      "google-photos-geodata-#{user.email}-from-#{from}-to-#{to}.json"
    end
  end
end
