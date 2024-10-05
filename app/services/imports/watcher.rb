# frozen_string_literal: true

class Imports::Watcher
  class UnsupportedSourceError < StandardError; end

  WATCHED_DIR_PATH = Rails.root.join('tmp/imports/watched')

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
      ['.gpx', '.json'].include?(File.extname(file))
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
    case file_name.split('.').last
    when 'json' then :geojson
    when 'gpx'  then :gpx
    else raise UnsupportedSourceError, 'Unsupported source '
    end
  end

  def raw_data(file_path, source)
    file = File.read(file_path)

    source.to_sym == :gpx ? Hash.from_xml(file) : JSON.parse(file)
  end
end
