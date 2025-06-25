# frozen_string_literal: true

require 'parallel'

class Users::ExportData::Exports
  def initialize(user, files_directory)
    @user = user
    @files_directory = files_directory
  end

  def call
    exports_with_files = user.exports.includes(:file_attachment).to_a

    # Only use parallel processing if we have multiple exports
    if exports_with_files.size > 1
      # Use fewer threads to avoid database connection issues
      results = Parallel.map(exports_with_files, in_threads: 2) do |export|
        process_export(export)
      end
      results
    else
      exports_with_files.map { |export| process_export(export) }
    end
  end

  private

  attr_reader :user, :files_directory

  def process_export(export)
    Rails.logger.info "Processing export #{export.name}"

    export_hash = export.as_json(except: %w[user_id id])

    if export.file.attached?
      add_file_data_to_export(export, export_hash)
    else
      add_empty_file_data_to_export(export_hash)
    end

    Rails.logger.info "Export #{export.name} processed"

    export_hash
  end

  def add_file_data_to_export(export, export_hash)
    sanitized_filename = generate_sanitized_export_filename(export)
    file_path = files_directory.join(sanitized_filename)

    begin
      download_and_save_export_file(export, file_path)
      add_file_metadata_to_export(export, export_hash, sanitized_filename)
    rescue StandardError => e
      Rails.logger.error "Failed to download export file #{export.id}: #{e.message}"
      export_hash['file_error'] = "Failed to download: #{e.message}"
    end
  end

  def add_empty_file_data_to_export(export_hash)
    export_hash['file_name'] = nil
    export_hash['original_filename'] = nil
  end

  def generate_sanitized_export_filename(export)
    "export_#{export.id}_#{export.file.blob.filename}".gsub(/[^0-9A-Za-z._-]/, '_')
  end

  def download_and_save_export_file(export, file_path)
    file_content = Imports::SecureFileDownloader.new(export.file).download_with_verification
    File.write(file_path, file_content, mode: 'wb')
  end

  def add_file_metadata_to_export(export, export_hash, sanitized_filename)
    export_hash['file_name'] = sanitized_filename
    export_hash['original_filename'] = export.file.blob.filename.to_s
    export_hash['file_size'] = export.file.blob.byte_size
    export_hash['content_type'] = export.file.blob.content_type
  end
end
