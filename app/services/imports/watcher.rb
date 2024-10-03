# frozen_string_literal: true

class Imports::Watcher
  class UnsupportedSourceError < StandardError; end

  WATCHED_DIR_PATH = Rails.root.join('tmp/imports/watched')

  def call
    %w[*.gpx *.json].each do |pattern|
      Dir[WATCHED_DIR_PATH.join(pattern)].each do |file_path|
        # valid file_name example: "email@dawarich.app_2024-01-01-2024-01-31.json"
        file_name = File.basename(file_path)

        user = find_user(file_name)
        next unless user

        import = find_or_initialize_import(user, file_name)

        next if import.persisted?

        import_id = set_import_attributes(import, file_path, file_name)

        ImportJob.perform_later(user.id, import_id)
      end
    end
  end

  private

  def find_user(file_name)
    email = file_name.split('_').first

    User.find_by(email:)
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

    source == :gpx ? Hash.from_xml(file) : JSON.parse(file)
  end
end
