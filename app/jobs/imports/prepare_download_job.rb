# frozen_string_literal: true

class Imports::PrepareDownloadJob < ApplicationJob
  queue_as :imports

  def perform(import_id, source_blob_id)
    import = Import.find_by(id: import_id)
    return unless import

    import.with_source_file_lock do
      import.reload
      return unless import.file.attached? && import.file.blob_id == source_blob_id

      begin
        Imports::Download.new(import).prepare
      ensure
        import.update_columns(download_preparation_pending: false)
      end
    end
  end
end
