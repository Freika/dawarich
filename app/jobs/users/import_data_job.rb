# frozen_string_literal: true

class Users::ImportDataJob < ApplicationJob
  queue_as :imports

  sidekiq_options retry: false

  def perform(import_id)
    import = Import.find(import_id)
    user = import.user

    archive_path = download_import_archive(import)

    raise StandardError, "Archive file not found: #{archive_path}" unless File.exist?(archive_path)

    import_stats = Users::ImportData.new(user, archive_path).import
    User.where(id: user.id).update_all(points_count: user.points.count)

    Rails.logger.info "Import completed successfully for user #{user.email}: #{import_stats}"
  rescue ActiveRecord::RecordNotFound => e
    ExceptionReporter.call(e, "Import job failed for import_id #{import_id} - import not found")

    raise e
  rescue StandardError => e
    handle_import_failure(import, user, e)

    raise e
  ensure
    cleanup_archive(archive_path)
  end

  private

  def handle_import_failure(import, user, error)
    user_id = user&.id || import&.user_id || 'unknown'
    ExceptionReporter.call(error, "Import job failed for user #{user_id}")

    import&.update!(status: :failed, error_message: error.message)
    create_import_failed_notification(user, error)
  end

  def cleanup_archive(archive_path)
    return unless archive_path && File.exist?(archive_path)

    File.delete(archive_path)
    Rails.logger.info "Cleaned up archive file: #{archive_path}"
  end

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
      title: I18n.t('jobs.users.import_data_job.data_import_failed'),
      content: I18n.t('jobs.users.import_data_job.your_data_import_failed_with_error_message_please_check_the',
                      message: error.message),
      kind: :error
    ).call
  end
end
