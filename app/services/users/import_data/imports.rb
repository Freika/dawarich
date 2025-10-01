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

    # Preload existing imports to avoid N+1 queries
    @existing_imports_cache = load_existing_imports

    imports_data.each do |import_data|
      next unless import_data.is_a?(Hash)

      # Normalize created_at for consistent cache key lookup
      created_at_normalized = normalize_created_at(import_data['created_at'])
      cache_key = import_cache_key(import_data['name'], import_data['source'], created_at_normalized)
      existing_import = @existing_imports_cache[cache_key]

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

  def load_existing_imports
    # Extract import identifiers from imports_data and normalize created_at
    import_keys = imports_data.select { |id| id.is_a?(Hash) && id['name'].present? && id['source'].present? }
                              .map do |id|
                                # Normalize created_at to string for consistent comparison
                                created_at_normalized = normalize_created_at(id['created_at'])
                                { name: id['name'], source: id['source'], created_at: created_at_normalized }
                              end

    return {} if import_keys.empty?

    # Build a hash for quick lookup
    cache = {}

    # Build OR conditions using Arel to fetch all matching imports in a single query
    arel_table = Import.arel_table
    conditions = import_keys.map do |key|
      condition = arel_table[:user_id].eq(user.id)
                                      .and(arel_table[:name].eq(key[:name]))
                                      .and(arel_table[:source].eq(key[:source]))

      # Handle created_at being nil
      if key[:created_at].nil?
        condition.and(arel_table[:created_at].eq(nil))
      else
        # Parse the string back to Time for querying
        condition.and(arel_table[:created_at].eq(Time.zone.parse(key[:created_at])))
      end
    end.reduce { |result, condition| result.or(condition) }

    # Fetch all matching imports in a single query
    Import.where(conditions).find_each do |import|
      # Normalize created_at from database for cache key
      created_at_normalized = normalize_created_at(import.created_at)
      cache_key = import_cache_key(import.name, import.source, created_at_normalized)
      cache[cache_key] = import
    end

    cache
  end

  def normalize_created_at(created_at)
    return nil if created_at.nil?

    # Convert to string in ISO8601 format for consistent comparison
    time = created_at.is_a?(String) ? Time.zone.parse(created_at) : created_at
    time&.iso8601
  end

  def import_cache_key(name, source, created_at)
    "#{name}_#{source}_#{created_at}"
  end

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
      # Prosopite detects N+1 queries in ActiveStorage's internal operations
      # These are unavoidable and part of ActiveStorage's design
      Prosopite.pause if defined?(Prosopite)

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
    ensure
      Prosopite.resume if defined?(Prosopite)
    end
  end
end
