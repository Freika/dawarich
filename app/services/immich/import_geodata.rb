# frozen_string_literal: true

class Immich::ImportGeodata
  attr_reader :user, :immich_api_base_url, :immich_api_key

  def initialize(user)
    @user = user
    @immich_api_base_url = "#{user.settings['immich_url']}/api"
    @immich_api_key = user.settings['immich_api_key']
  end

  def call
    raise ArgumentError, 'Immich API key is missing' if immich_api_key.blank?
    raise ArgumentError, 'Immich URL is missing'     if user.settings['immich_url'].blank?

    immich_data       = retrieve_immich_data
    immich_data_json  = parse_immich_data(immich_data)
    file_name         = file_name(immich_data_json)
    import            = user.imports.find_or_initialize_by(name: file_name, source: :immich_api)

    create_import_failed_notification(import.name) and return unless import.new_record?

    import.raw_data = immich_data_json
    import.save!
    ImportJob.perform_later(user.id, import.id)
  end

  private

  def headers
    {
      'x-api-key' => immich_api_key,
      'accept' => 'application/json'
    }
  end

  def retrieve_immich_data
    1970.upto(Date.today.year).flat_map do |year|
      (1..12).flat_map do |month_number|
        url = "#{immich_api_base_url}/timeline/bucket?size=MONTH&timeBucket=#{year}-#{month_number}-01"

        JSON.parse(HTTParty.get(url, headers:).body)
      end
    end
  end

  def valid?(asset)
    asset.dig('exifInfo', 'latitude') &&
      asset.dig('exifInfo', 'longitude') &&
      asset.dig('exifInfo', 'dateTimeOriginal')
  end

  def parse_immich_data(immich_data)
    geodata = immich_data.map do |asset|
      log_no_data and next if asset_invalid?(asset)
      next unless valid?(asset)

      extract_geodata(asset)
    end

    geodata.compact.sort_by { |data| data[:timestamp] }
  end

  def asset_invalid?(bucket)
    bucket.is_a?(Hash) && bucket['statusCode'] == 404
  end

  def extract_geodata(asset)
    {
      latitude: asset.dig('exifInfo', 'latitude'),
      longitude: asset.dig('exifInfo', 'longitude'),
      timestamp: Time.zone.parse(asset.dig('exifInfo', 'dateTimeOriginal')).to_i
    }
  end

  def log_no_data
    Rails.logger.debug 'No data found'
  end

  def create_import_failed_notification(import_name)
    Notifications::Create.new(
      user:,
      kind: :info,
      title: 'Import was not created',
      content: "Import with the same name (#{import_name}) already exists. If you want to proceed, delete the existing import and try again."
    ).call
  end

  def file_name(immich_data_json)
    from              = Time.zone.at(immich_data_json.first[:timestamp]).to_date
    to                = Time.zone.at(immich_data_json.last[:timestamp]).to_date

    "immich-geodata-#{user.email}-from-#{from}-to-#{to}.json"
  end
end
