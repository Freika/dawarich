# frozen_string_literal: true

class DataMigrations::UnwrapLegacyImportsJob < ApplicationJob
  queue_as :data_migrations

  def perform
    renamed = rename_legacy_imports
    reset = reset_fallback_downloads

    Rails.logger.info("Unwrapped legacy imports: #{renamed} renamed, #{reset} downloads reset")
  end

  private

  def rename_legacy_imports
    renamed = 0

    Import.where("name LIKE '%.zip'").includes(file_attachment: :blob).find_each do |import|
      next unless import.file.attached?

      name = Imports::Download.new(import).unwrapped_name
      next if name.nil? || Import.exists?(user_id: import.user_id, name:)

      import.update_columns(name:)
      renamed += 1
    end

    renamed
  end

  def reset_fallback_downloads
    ActiveStorage::Attachment
      .where(record_type: 'Import', name: 'prepared_download')
      .where(<<~SQL.squish)
        EXISTS (
          SELECT 1 FROM active_storage_attachments files
          WHERE files.record_type = 'Import' AND files.name = 'file'
            AND files.record_id = active_storage_attachments.record_id
            AND files.blob_id = active_storage_attachments.blob_id
        )
      SQL
      .delete_all
  end
end
