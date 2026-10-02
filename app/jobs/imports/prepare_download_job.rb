# frozen_string_literal: true

class Imports::PrepareDownloadJob < ApplicationJob
  queue_as :imports
  retry_on Imports::DownloadCommands::Busy, wait: 5.seconds, attempts: :unlimited

  def perform(import_id, source_blob_id, native_fallback: false, expected_user_id: nil)
    Imports::DownloadCommands.perform(import_id, source_blob_id, event_id: job_id, native_fallback:, expected_user_id:)
  end
end
