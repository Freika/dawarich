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
    export_data['name'].present? && export_data['file_format'].present? && export_data['status'].present?
  end

  def create_export_record(export_data)
    export_attributes = prepare_export_attributes(export_data)
    record = user.exports.new(export_attributes)
    if record.created? || record.processing?
      record.assign_attributes(status: :failed, error_message: I18n.t('ux_p2.exports.restored_incomplete'))
    end
    record.save!
    record
  end

  def prepare_export_attributes(export_data)
    export_data.except(
      'file_name',
      'original_filename',
      'file_size',
      'content_type',
      'file_error',
      'import_id',
      'import_scope',
      'import_scope_unavailable',
      'skip_background_processing'
    ).merge(restored_import_scope(export_data)).merge(user: user, skip_background_processing: true)
  end

  # Numeric database IDs from an archive are never portable or authoritative.
  # Match the same identity used by Imports restore; missing/legacy scopes stay closed.
  def restored_import_scope(data)
    scope = data['import_scope']
    scoped = data.key?('import_scope') || data['import_id'].present? || data['import_scope_unavailable'] == true
    return { import_id: nil, import_scope_unavailable: false } unless scoped

    reference = scope['reference'] if scope.is_a?(Hash)
    if reference.is_a?(Hash) && reference['name'].is_a?(String) && reference['name'].present? &&
       reference['created_at'].is_a?(String) && reference['created_at'].present? && reference.key?('source') &&
       (reference['source'].nil? || Import.sources.key?(reference['source']))
      matches = user.imports.where(reference.slice('name', 'source', 'created_at')).limit(2).to_a
      return { import_id: matches.first.id, import_scope_unavailable: false } if matches.one?
    end
    { import_id: nil, import_scope_unavailable: true }
  end

  def restore_export_file(export_record, export_data)
    file_path = Users::ImportData::PathSafety.safe_basename_path(
      files_directory, export_data['file_name']
    )

    unless file_path && File.exist?(file_path)
      Rails.logger.warn "Export file not found or unsafe: #{export_data['file_name']}"
      return false
    end

    begin
      safe_filename = File.basename(
        (export_data['original_filename'] || export_data['file_name']).to_s
      )
      export_record.file.attach(
        io: File.open(file_path),
        filename: safe_filename,
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
