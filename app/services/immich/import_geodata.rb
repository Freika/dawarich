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

    immich_data = retrieve_immich_data

    log_no_data and return if immich_data.empty?

    write_raw_data(immich_data)

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
    url = "#{immich_api_base_url}/search/metadata"
    page = 1
    data = []
    max_pages = 1000 # Prevent infinite loop

    while page <= max_pages
      Rails.logger.debug "Retrieving next page: #{page}"
      body = request_body(page)
      response = JSON.parse(HTTParty.post(url, headers: headers, body: body).body)

      items = response.dig('assets', 'items')
      Rails.logger.debug "#{items.size} items found"

      break if items.empty?

      data << items

      Rails.logger.debug "next_page: #{response.dig('assets', 'nextPage')}"

      page += 1

      Rails.logger.debug "#{data.flatten.size} data size"
    end

    data.flatten
  end

  def request_body(page)
    {
      createdAfter: '1970-01-01',
      size: 1000,
      page: page,
      order: 'asc',
      withExif: true
    }
  end

  def parse_immich_data(immich_data)
    geodata = immich_data.map do |asset|
      next unless valid?(asset)

      extract_geodata(asset)
    end

    geodata.compact.sort_by { |data| data[:timestamp] }
  end

  def valid?(asset)
    asset.dig('exifInfo', 'latitude') &&
      asset.dig('exifInfo', 'longitude') &&
      asset.dig('exifInfo', 'dateTimeOriginal')
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

  def write_raw_data(immich_data)
    File.open("tmp/imports/immich_raw_data_#{Time.current}_#{user.email}.json", 'w') do |file|
      file.write(immich_data.to_json)
    end
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
