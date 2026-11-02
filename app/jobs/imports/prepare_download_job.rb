# frozen_string_literal: true

class Imports::PrepareDownloadJob < ApplicationJob
  queue_as :imports

  def perform(import_id, source_blob_id)
    ActiveRecord::Base.with_advisory_lock("import-download:#{import_id}", timeout_seconds: 0) do
      import = Import.find_by(id: import_id)
      return unless import&.file&.attached?
      return unless import.file.blob_id == source_blob_id

      Imports::Download.new(import).prepare
    end
  end
end
