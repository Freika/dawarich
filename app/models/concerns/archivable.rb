# frozen_string_literal: true

module Archivable
  extend ActiveSupport::Concern

  included do
    belongs_to :raw_data_archive,
               class_name: 'Points::RawDataArchive',
               optional: true

    scope :archived, -> { where(raw_data_archived: true) }
    scope :not_archived, -> { where(raw_data_archived: false) }
    scope :with_archived_raw_data, lambda {
      includes(raw_data_archive: { file_attachment: :blob })
    }

    before_save :reset_archival_on_raw_data_change
  end

  UPSERT_CONFLICT_KEYS = %i[lonlat timestamp user_id].freeze
  UPSERT_MAX_RETRIES = 3
  UPSERT_BACKOFF_BASE = 0.1
  UPSERT_BACKOFF_JITTER = 0.05
  UPSERT_CONTENTION_ERRORS = [
    ActiveRecord::Deadlocked,
    ActiveRecord::LockWaitTimeout,
    ActiveRecord::QueryCanceled
  ].freeze

  class_methods do
    # Bulk-ingest counterpart of the reset_archival_on_raw_data_change
    # callback, which raw SQL upserts bypass: on conflict, archival flags are
    # reset only when the incoming raw_data actually differs from the stored
    # one, so a stale archive is never left pointing at diverged data.
    def archival_safe_upsert_all(rows, returning:)
      return [] if rows.empty?

      rows = rows.sort_by { |row| dedup_key(row).map { |value| value.nil? ? Float::INFINITY : value } }
      update_columns = rows.first.keys.map(&:to_sym) - UPSERT_CONFLICT_KEYS - %i[created_at]

      set_clauses = update_columns.map do |column|
        quoted = connection.quote_column_name(column)
        "#{quoted} = excluded.#{quoted}"
      end
      set_clauses << '"updated_at" = CURRENT_TIMESTAMP' unless update_columns.include?(:updated_at)
      set_clauses.concat(archival_reset_clauses) if update_columns.include?(:raw_data)

      with_write_contention_retry do
        upsert_all(
          rows,
          unique_by: UPSERT_CONFLICT_KEYS,
          on_duplicate: Arel.sql(set_clauses.join(', ')),
          returning: returning
        )
      end
    end

    private

    def with_write_contention_retry
      retries = 0

      begin
        yield
      rescue *UPSERT_CONTENTION_ERRORS => e
        retries += 1
        raise e if retries > UPSERT_MAX_RETRIES

        sleep((UPSERT_BACKOFF_BASE * retries) + (rand * UPSERT_BACKOFF_JITTER))
        retry
      end
    end

    def archival_reset_clauses
      table = connection.quote_table_name(table_name)
      raw_data_changed = "#{table}.\"raw_data\" IS DISTINCT FROM excluded.\"raw_data\""

      [
        "\"raw_data_archived\" = CASE WHEN #{raw_data_changed} THEN FALSE " \
        "ELSE #{table}.\"raw_data_archived\" END",
        "\"raw_data_archive_id\" = CASE WHEN #{raw_data_changed} THEN NULL " \
        "ELSE #{table}.\"raw_data_archive_id\" END"
      ]
    end
  end

  # Main method: Get raw_data with fallback to archive
  # Use this instead of point.raw_data when you need archived data
  def raw_data_with_archive
    return raw_data if raw_data.present? || !raw_data_archived?

    fetch_archived_raw_data
  end

  # Restore archived data back to database column
  def restore_raw_data!(value)
    update!(
      raw_data: value,
      raw_data_archived: false,
      raw_data_archive_id: nil
    )
  end

  private

  def fetch_archived_raw_data
    # Check temporary restore cache first (for migrations)
    cached = check_temporary_restore_cache
    return cached if cached

    fetch_from_archive_file
  rescue StandardError => e
    handle_archive_fetch_error(e)
  end

  def reset_archival_on_raw_data_change
    return if new_record?
    return unless raw_data_archived? && will_save_change_to_raw_data?

    self.raw_data_archived = false
    self.raw_data_archive_id = nil
  end

  def check_temporary_restore_cache
    Rails.cache.read("raw_data:temp:#{user_id}:#{id}")
  end

  def fetch_from_archive_file
    return {} unless raw_data_archive&.file&.attached?

    # Download and search through JSONL
    compressed_content = Points::RawData::Encryption.decrypt_if_needed(
      raw_data_archive.file.blob.download, raw_data_archive
    )
    io = StringIO.new(compressed_content)
    gz = Zlib::GzipReader.new(io)

    begin
      result = nil
      gz.each_line do |line|
        data = JSON.parse(line)
        if data['id'] == id
          result = data['raw_data']
          break
        end
      end
      result || {}
    ensure
      gz.close
    end
  end

  def handle_archive_fetch_error(error)
    ExceptionReporter.call(error, "Failed to fetch archived raw_data for Point ID #{id}")

    {} # Graceful degradation
  end
end
