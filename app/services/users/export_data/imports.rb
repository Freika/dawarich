# frozen_string_literal: true

class Users::ExportData::Imports
  def initialize(user, files_directory)
    @user = user
    @files_directory = files_directory
  end

  def call
    user.imports.includes(:file_attachment).map do |import|
      process_import(import)
    end
  end

  private

  attr_reader :user, :files_directory

  def process_import(import)
    Rails.logger.info "Processing import #{import.name}"

    import_hash = import.as_json(except: %w[user_id raw_data id])

    if import.file.attached?
      add_file_data_to_import(import, import_hash)
    else
      add_empty_file_data_to_import(import_hash)
    end

    Rails.logger.info "Import #{import.name} processed"

    import_hash
  end

  def add_file_data_to_import(import, import_hash)
    sanitized_filename = generate_sanitized_filename(import)
    file_path = files_directory.join(sanitized_filename)

    begin
      download_and_save_import_file(import, file_path)
      add_file_metadata_to_import(import, import_hash, sanitized_filename)
    rescue StandardError => e
      Rails.logger.error "Failed to download import file #{import.id}: #{e.message}"
      import_hash['file_error'] = "Failed to download: #{e.message}"
    end
  end

  def add_empty_file_data_to_import(import_hash)
    import_hash['file_name'] = nil
    import_hash['original_filename'] = nil
  end

  def generate_sanitized_filename(import)
    "import_#{import.id}_#{import.file.blob.filename}".gsub(/[^0-9A-Za-z._-]/, '_')
  end

  def download_and_save_import_file(import, file_path)
    file_content = Imports::SecureFileDownloader.new(import.file).download_with_verification
    File.write(file_path, file_content, mode: 'wb')
  end

  def add_file_metadata_to_import(import, import_hash, sanitized_filename)
    import_hash['file_name'] = sanitized_filename
    import_hash['original_filename'] = import.file.blob.filename.to_s
    import_hash['file_size'] = import.file.blob.byte_size
    import_hash['content_type'] = import.file.blob.content_type
  end
end
