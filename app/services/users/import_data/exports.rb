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
      result = import_single_export(export_data)
      next unless result

      exports_created += 1
      files_restored += result[:file_restored] ? 1 : 0
    end

    Rails.logger.info "Exports import completed. Created: #{exports_created}, Files: #{files_restored}"
    [exports_created, files_restored]
  end

  private

  attr_reader :user, :exports_data, :files_directory

  def import_single_export(export_data)
    return unless export_data.is_a?(Hash) && valid_export_data?(export_data)
    return if already_imported?(export_data)

    export_record = create_export_record(export_data)
    file_restored = export_data['file_name'] && restore_export_file(export_record, export_data)

    Rails.logger.debug "Created export: #{export_record.name}"
    { file_restored: file_restored }
  rescue ArgumentError, ActiveModel::UnknownAttributeError, ActiveRecord::RecordInvalid => e
    Rails.logger.warn "Skipping invalid export data: #{e.message}"
    nil
  end

  def already_imported?(export_data)
    existing = user.exports.find_by(name: export_data['name'], created_at: export_data['created_at'])
    return false unless existing

    Rails.logger.debug "Export already exists: #{export_data['name']}"
    true
  end

  def valid_export_data?(export_data)
    # Minimum required fields for a valid export
    export_data['name'].present? || export_data['file_format'].present? || export_data['status'].present?
  end

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
      export_record.file.attach(
        io: File.open(file_path),
        filename: export_data['original_filename'] || export_data['file_name'],
        content_type: export_data['content_type'] || 'application/octet-stream'
      )

      Rails.logger.debug "Restored file for export: #{export_record.name}"

      true
    rescue StandardError => e
      ExceptionReporter.call(e, 'Export file restoration failed')

      false
    end
  end
end
