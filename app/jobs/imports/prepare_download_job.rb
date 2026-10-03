# frozen_string_literal: true

class Imports::PrepareDownloadJob < ApplicationJob
  queue_as :imports

  retry_on Imports::DownloadCommands::Busy, wait: :polynomially_longer,
                                            attempts: Imports::BusyRetry::ATTEMPTS do |job, _error|
    Rails.logger.warn("[imports] import #{job.arguments.first}: download preparation stopped, " \
                      'another preparation kept it busy')
  end

  def perform(import_id, source_blob_id, native_fallback: false, expected_user_id: nil)
    return legacy(import_id, source_blob_id) unless Import.find_by(id: import_id)&.gpx?

    Imports::DownloadCommands.perform(import_id, source_blob_id, event_id: job_id, native_fallback:, expected_user_id:)
  end

  private

  def legacy(import_id, source_blob_id)
    PhoenixLease.try_hold("import-download:#{import_id}") do
      import = Import.find_by(id: import_id)
      return unless import&.file&.attached?
      return unless import.file.blob_id == source_blob_id

      Imports::Download.new(import).prepare
    end
  end
end
