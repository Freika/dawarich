# frozen_string_literal: true

module Archivable
  extend ActiveSupport::Concern

  included do
    # Associations
    belongs_to :raw_data_archive,
      class_name: 'Points::RawDataArchive',
      foreign_key: :raw_data_archive_id,
      optional: true

    # Scopes
    scope :archived, -> { where(raw_data_archived: true) }
    scope :not_archived, -> { where(raw_data_archived: false) }
    scope :with_archived_raw_data, -> {
      includes(raw_data_archive: { file_attachment: :blob })
    }
  end

  # Main method: Get raw_data with fallback to archive
  # Use this instead of point.raw_data when you need archived data
  def raw_data_with_archive
    # If raw_data is present in DB, use it
    return raw_data if raw_data.present? || !raw_data_archived?

    # Otherwise fetch from archive
    fetch_archived_raw_data
  end

  # Alias for convenience (optional)
  alias_method :archived_raw_data, :raw_data_with_archive

  # Restore archived data back to database column
  def restore_raw_data!(value)
    update!(
      raw_data: value,
      raw_data_archived: false,
      raw_data_archive_id: nil
    )
  end

  # Cache key for long-term archive caching
  def archive_cache_key
    "raw_data:archive:#{self.class.name.underscore}:#{id}"
  end

  private

  def fetch_archived_raw_data
    # Check temporary restore cache first (for migrations)
    cached = check_temporary_restore_cache
    return cached if cached

    # Check long-term cache (1 day TTL)
    Rails.cache.fetch(archive_cache_key, expires_in: 1.day) do
      fetch_from_archive_file
    end
  rescue StandardError => e
    handle_archive_fetch_error(e)
  end

  def check_temporary_restore_cache
    return nil unless respond_to?(:timestamp)

    recorded_time = Time.at(timestamp)
    cache_key = "raw_data:temp:#{user_id}:#{recorded_time.year}:#{recorded_time.month}:#{id}"
    Rails.cache.read(cache_key)
  end

  def fetch_from_archive_file
    return {} unless raw_data_archive&.file&.attached?

    # Download and search through JSONL
    compressed_content = raw_data_archive.file.blob.download
    io = StringIO.new(compressed_content)
    gz = Zlib::GzipReader.new(io)

    result = nil
    gz.each_line do |line|
      data = JSON.parse(line)
      if data['id'] == id
        result = data['raw_data']
        break
      end
    end

    gz.close
    result || {}
  end

  def handle_archive_fetch_error(error)
    Rails.logger.error(
      "Failed to fetch archived raw_data for #{self.class.name} #{id}: #{error.message}"
    )
    Sentry.capture_exception(error) if defined?(Sentry)

    {} # Graceful degradation
  end
end
