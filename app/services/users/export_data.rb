# frozen_string_literal: true

require 'zip'

class Users::ExportData
  def initialize(user)
    @user = user
    @export_directory = export_directory
    @files_directory = files_directory
  end

  def export
    # TODO: Implement
    # 1. Export user settings
    # 2. Export user points
    # 3. Export user areas
    # 4. Export user visits
    # 7. Export user trips
    # 8. Export user places
    # 9. Export user notifications
    # 10. Export user stats

    # 11. Zip all the files

    FileUtils.mkdir_p(files_directory)

    begin
      data = {}

      data[:settings] = user.safe_settings.settings
      data[:points] = nil
      data[:areas] = nil
      data[:visits] = nil
      data[:imports] = serialized_imports
      data[:exports] = serialized_exports
      data[:trips] = nil
      data[:places] = nil

      json_file_path = export_directory.join('data.json')
      File.write(json_file_path, data.to_json)

      zip_file_path = export_directory.join('export.zip')
      create_zip_archive(zip_file_path)

      # Move the zip file to a final location (e.g., tmp root) before cleanup
      final_zip_path = Rails.root.join('tmp', "#{user.email}_export_#{Time.current.strftime('%Y%m%d_%H%M%S')}.zip")
      FileUtils.mv(zip_file_path, final_zip_path)

      final_zip_path
    ensure
      cleanup_temporary_files
    end
  end

  private

  attr_reader :user

  def export_directory
    @export_directory ||= Rails.root.join('tmp', "#{user.email}_#{Time.current.strftime('%Y%m%d_%H%M%S')}")
  end

  def files_directory
    @files_directory ||= export_directory.join('files')
  end

  def serialized_exports
    exports_data = user.exports.includes(:file_attachment).map do |export|
      process_export(export)
    end

    {
      exports: exports_data,
      export_directory: export_directory.to_s,
      files_directory: files_directory.to_s
    }
  end

  def process_export(export)
    Rails.logger.info "Processing export #{export.name}"

    # Only include essential attributes, exclude any potentially large fields
    export_hash = export.as_json(except: %w[user_id])

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

  def serialized_imports
    imports_data = user.imports.includes(:file_attachment).map do |import|
      process_import(import)
    end

    {
      imports: imports_data,
      export_directory: export_directory.to_s,
      files_directory: files_directory.to_s
    }
  end

  def process_import(import)
    Rails.logger.info "Processing import #{import.name}"

    # Only include essential attributes, exclude large fields like raw_data
    import_hash = import.as_json(except: %w[user_id raw_data])

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

  def create_zip_archive(zip_file_path)
    Zip::File.open(zip_file_path, Zip::File::CREATE) do |zipfile|
      Dir.glob(export_directory.join('**', '*')).each do |file|
        next if File.directory?(file) || file == zip_file_path.to_s

        relative_path = file.sub(export_directory.to_s + '/', '')
        zipfile.add(relative_path, file)
      end
    end
  end

  def cleanup_temporary_files
    return unless File.directory?(export_directory)

    Rails.logger.info "Cleaning up temporary export directory: #{export_directory}"
    FileUtils.rm_rf(export_directory)
  rescue StandardError => e
    Rails.logger.error "Failed to cleanup temporary files: #{e.message}"
    # Don't re-raise the error as cleanup failure shouldn't break the export
  end
end
