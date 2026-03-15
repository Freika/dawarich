# frozen_string_literal: true

class Users::ImportData::RawDataArchives
  def initialize(user, archives_data, files_directory)
    @user = user
    @archives_data = archives_data
    @files_directory = files_directory
  end

  def call
    return [0, 0] unless archives_data.is_a?(Array)

    Rails.logger.info "Importing #{archives_data.size} raw data archives for user: #{user.email}"

    archives_created = 0
    files_restored = 0

    archives_data.each do |archive_data|
      next unless archive_data.is_a?(Hash)

      existing = find_existing_archive(archive_data)

      if existing
        Rails.logger.debug "Raw data archive already exists: #{archive_data['year']}/#{archive_data['month']}"
        next
      end

      begin
        archive_record = create_archive_record(archive_data)
        archives_created += 1

        files_restored += 1 if archive_data['file_name'] && restore_archive_file(archive_record, archive_data)
      rescue ActiveRecord::RecordInvalid => e
        Rails.logger.warn "Skipping invalid raw data archive: #{e.message}"
        next
      end
    end

    Rails.logger.info "Raw data archives import completed. Created: #{archives_created}, Files: #{files_restored}"
    [archives_created, files_restored]
  end

  private

  attr_reader :user, :archives_data, :files_directory

  def find_existing_archive(archive_data)
    user.raw_data_archives.find_by(
      year: archive_data['year'],
      month: archive_data['month'],
      chunk_number: archive_data['chunk_number']
    )
  end

  def create_archive_record(archive_data)
    attributes = archive_data.except(
      'file_name', 'original_filename', 'content_type'
    )

    user.raw_data_archives.create!(attributes)
  end

  def restore_archive_file(archive_record, archive_data)
    file_path = files_directory.join(archive_data['file_name'])

    unless File.exist?(file_path)
      Rails.logger.warn "Raw data archive file not found: #{archive_data['file_name']}"
      return false
    end

    archive_record.file.attach(
      io: File.open(file_path),
      filename: archive_data['original_filename'] || archive_data['file_name'],
      content_type: archive_data['content_type'] || 'application/gzip'
    )

    true
  rescue StandardError => e
    ExceptionReporter.call(e, 'Raw data archive file restoration failed')
    false
  end
end
