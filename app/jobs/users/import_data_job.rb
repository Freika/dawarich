# frozen_string_literal: true

class Users::ImportDataJob < ApplicationJob
  queue_as :imports

  sidekiq_options retry: false

  def perform(import_id)
    import = Import.find(import_id)
    user = import.user

    archive_path = download_import_archive(import)

    unless File.exist?(archive_path)
      raise StandardError, "Archive file not found: #{archive_path}"
    end

    import_stats = Users::ImportData.new(user, archive_path).import

    User.reset_counters(user.id, :points)

    Rails.logger.info "Import completed successfully for user #{user.email}: #{import_stats}"
  rescue ActiveRecord::RecordNotFound => e
    ExceptionReporter.call(e, "Import job failed for import_id #{import_id} - import not found")

    raise e
  rescue StandardError => e
    user_id = user&.id || import&.user_id || 'unknown'
    ExceptionReporter.call(e, "Import job failed for user #{user_id}")

    create_import_failed_notification(user, e)

    raise e
  ensure
    if archive_path && File.exist?(archive_path)
      File.delete(archive_path)

      Rails.logger.info "Cleaned up archive file: #{archive_path}"
    end
  end

  private

  def download_import_archive(import)
    require 'tmpdir'

    timestamp = Time.current.to_i
    filename = "user_import_#{import.user_id}_#{import.id}_#{timestamp}.zip"
    temp_path = File.join(Dir.tmpdir, filename)

    File.open(temp_path, 'wb') do |file_handle|
      import.file.download do |chunk|
        file_handle.write(chunk)
      end
    end

    temp_path
  end

  def create_import_failed_notification(user, error)
    ::Notifications::Create.new(
      user: user,
      title: 'Data import failed',
      content: "Your data import failed with error: #{error.message}. Please check the archive format and try again.",
      kind: :error
    ).call
  end
end
