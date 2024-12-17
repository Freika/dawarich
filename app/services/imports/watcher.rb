# frozen_string_literal: true

class Imports::Watcher
  class UnsupportedSourceError < StandardError; end

  WATCHED_DIR_PATH = Rails.root.join('tmp/imports/watched')
  SUPPORTED_FORMATS = %w[.gpx .json .rec].freeze

  def call
    user_directories.each do |user_email|
      user = User.find_by(email: user_email)
      next unless user

      user_directory_path = File.join(WATCHED_DIR_PATH, user_email)
      file_names = file_names(user_directory_path)

      file_names.each do |file_name|
        process_file(user, user_directory_path, file_name)
      end
    end
  end

  private

  def user_directories
    Dir.entries(WATCHED_DIR_PATH).select do |entry|
      path = File.join(WATCHED_DIR_PATH, entry)
      File.directory?(path) && !['.', '..'].include?(entry)
    end
  end

  def find_user(file_name)
    email = file_name.split('_').first

    User.find_by(email:)
  end

  def file_names(directory_path)
    Dir.entries(directory_path).select do |file|
      SUPPORTED_FORMATS.include?(File.extname(file))
    end
  end

  def process_file(user, directory_path, file_name)
    file_path = File.join(directory_path, file_name)
    import = Import.find_or_initialize_by(user:, name: file_name)

    return if import.persisted?

    import.source = source(file_name)
   
    import.raw_data = raw_data(file_path, import.source)

    import.save!

    ImportJob.perform_later(user.id, import.id)
  end

  def find_or_initialize_import(user, file_name)
    import_name = file_name.split('_')[1..].join('_')

    Import.find_or_initialize_by(user:, name: import_name)
  end

  def set_import_attributes(import, file_path, file_name)
    source = source(file_name)

    import.source = source
    import.raw_data = raw_data(file_path, source)

    import.save!

    import.id
  end

  def source(file_name)
    case file_name.split('.').last.downcase
    when 'json' 
      if file_name.match?(/location-history/i)
        :google_phone_takeout
      elsif file_name.match?(/Records/i)
        :google_records
      elsif file_name.match?(/\d{4}_\w+/i)
        :google_semantic_history
      else
        :geojson
    end
    when 'rec' then :owntracks
    when 'gpx' then :gpx
    else raise UnsupportedSourceError, 'Unsupported source '
    end
  end

  def raw_data(file_path, source)
    file = File.read(file_path)

    case source.to_sym
    when :gpx
      Hash.from_xml(file)
    when :json, :geojson, :google_phone_takeout, :google_records, :google_semantic_history
      JSON.parse(file)
    when :owntracks
      OwnTracks::RecParser.new(file).call
    else
      raise UnsupportedSourceError, "Unsupported source: #{source}"
    end
  end
end