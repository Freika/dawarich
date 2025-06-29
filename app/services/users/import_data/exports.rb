# frozen_string_literal: true

class Users::ImportData::Exports
  def initialize(user, exports_data, files_directory)
    @user = user
    @exports_data = exports_data
    @files_directory = files_directory
  end

  def call
    return [0, 0] unless exports_data.is_a?(Array)

    Rails.logger.info "Importing #{exports_data.size} exports for user: #{user.email}"

    exports_created = 0
    files_restored = 0

    exports_data.each do |export_data|
      next unless export_data.is_a?(Hash)

      # Check if export already exists (match by name and created_at)
      existing_export = user.exports.find_by(
        name: export_data['name'],
        created_at: export_data['created_at']
      )

      if existing_export
        Rails.logger.debug "Export already exists: #{export_data['name']}"
        next
      end

      # Create new export
      export_record = create_export_record(export_data)
      exports_created += 1

      # Restore file if present
      if export_data['file_name'] && restore_export_file(export_record, export_data)
        files_restored += 1
      end

      Rails.logger.debug "Created export: #{export_record.name}"
    end

    Rails.logger.info "Exports import completed. Created: #{exports_created}, Files: #{files_restored}"
    [exports_created, files_restored]
  end

  private

  attr_reader :user, :exports_data, :files_directory

  def create_export_record(export_data)
    export_attributes = prepare_export_attributes(export_data)
    user.exports.create!(export_attributes)
  end

  def prepare_export_attributes(export_data)
    export_data.except(
      'file_name',
      'original_filename',
      'file_size',
      'content_type',
      'file_error'
    ).merge(user: user)
  end

  def restore_export_file(export_record, export_data)
    file_path = files_directory.join(export_data['file_name'])

    unless File.exist?(file_path)
      Rails.logger.warn "Export file not found: #{export_data['file_name']}"
      return false
    end

    begin
      # Attach the file to the export record
      export_record.file.attach(
        io: File.open(file_path),
        filename: export_data['original_filename'] || export_data['file_name'],
        content_type: export_data['content_type'] || 'application/octet-stream'
      )

      Rails.logger.debug "Restored file for export: #{export_record.name}"

      true
    rescue StandardError => e
      ExceptionReporter.call(e, "Export file restoration failed")

      false
    end
  end
end
