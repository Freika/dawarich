# frozen_string_literal: true

class Users::ImportData::Imports
  def initialize(user, imports_data, files_directory)
    @user = user
    @imports_data = imports_data
    @files_directory = files_directory
  end

  def call
    return [0, 0] unless imports_data.is_a?(Array)

    Rails.logger.info "Importing #{imports_data.size} imports for user: #{user.email}"

    imports_created = 0
    files_restored = 0

    imports_data.each do |import_data|
      next unless import_data.is_a?(Hash)

      existing_import = user.imports.find_by(
        name: import_data['name'],
        source: import_data['source'],
        created_at: import_data['created_at']
      )

      if existing_import
        Rails.logger.debug "Import already exists: #{import_data['name']}"
        next
      end

      import_record = create_import_record(import_data)
      next unless import_record # Skip if creation failed

      imports_created += 1

      files_restored += 1 if import_data['file_name'] && restore_import_file(import_record, import_data)
    end

    Rails.logger.info "Imports import completed. Created: #{imports_created}, Files restored: #{files_restored}"
    [imports_created, files_restored]
  end

  private

  attr_reader :user, :imports_data, :files_directory

  def create_import_record(import_data)
    import_attributes = prepare_import_attributes(import_data)

    begin
      import_record = user.imports.build(import_attributes)
      import_record.skip_background_processing = true
      import_record.save!
      Rails.logger.debug "Created import: #{import_record.name}"
      import_record
    rescue ActiveRecord::RecordInvalid => e
      Rails.logger.error "Failed to create import: #{e.message}"
      nil
    end
  end

  def prepare_import_attributes(import_data)
    import_data.except(
      'file_name',
      'original_filename',
      'file_size',
      'content_type',
      'file_error',
      'updated_at'
    ).merge(user: user)
  end

  def restore_import_file(import_record, import_data)
    file_path = files_directory.join(import_data['file_name'])

    unless File.exist?(file_path)
      Rails.logger.warn "Import file not found: #{import_data['file_name']}"
      return false
    end

    begin
      import_record.file.attach(
        io: File.open(file_path),
        filename: import_data['original_filename'] || import_data['file_name'],
        content_type: import_data['content_type'] || 'application/octet-stream'
      )

      Rails.logger.debug "Restored file for import: #{import_record.name}"

      true
    rescue StandardError => e
      ExceptionReporter.call(e, 'Import file restoration failed')

      false
    end
  end
end
