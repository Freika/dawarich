# frozen_string_literal: true

class Imports::DestroyJob < ApplicationJob
  queue_as :imports

  retry_on Imports::DestroyLegacy::Busy, wait: :polynomially_longer,
                                         attempts: Imports::BusyRetry::ATTEMPTS do |job, _error|
    options = job.arguments.second || {}
    Imports::BusyRetry.fail!(job.arguments.first, from: :deleting, user_id: options[:expected_user_id])
  end

  def perform(import_id, expected_user_id: nil, event_id: nil)
    import = Import.find_by(id: import_id)
    return unless import

    if Imports::DestroyLegacy.coordinated?(import)
      expected_user_id ||= import.user_id
      Imports::DestroyLegacy.perform(import, expected_user_id:, event_id:, job_event_id: job_id) { destroy(import) }
    else
      destroy(import)
    end
  rescue Imports::DestroyLegacy::Busy
    raise
  rescue ActiveRecord::RecordNotFound
    Rails.logger.warn "Import #{import_id} not found, may have already been deleted"
  rescue StandardError
    revert_deleting_status(import, expected_user_id)
    raise
  end

  private

  def destroy(import)
    import.deleting!
    broadcast_status_update(import)
    Imports::Destroy.new(import.user, import).call
    broadcast_deletion_complete(import)
  end

  def revert_deleting_status(import, expected_user_id)
    return unless import && Import.exists?(import.id)
    return if expected_user_id && !(User.exists?(id: expected_user_id) &&
                                    Import.exists?(id: import.id, user_id: expected_user_id))

    import.failed!
    broadcast_status_update(import)
  rescue StandardError => e
    Rails.logger.warn "Failed to revert deleting status for import #{import.id}: #{e.message}"
  end

  def broadcast_status_update(import)
    ImportsChannel.broadcast_to(
      import.user,
      {
        action: 'status_update',
        import: {
          id: import.id,
          status: import.status
        }
      }
    )

    Turbo::StreamsChannel.broadcast_replace_to(
      [import.user, :imports],
      target: ActionView::RecordIdentifier.dom_id(import),
      partial: 'imports/table_row',
      locals: { import: import, timezone: import.user.safe_settings.timezone }
    )
  end

  def broadcast_deletion_complete(import)
    ImportsChannel.broadcast_to(
      import.user,
      {
        action: 'delete',
        import: {
          id: import.id
        }
      }
    )

    Turbo::StreamsChannel.broadcast_remove_to(
      [import.user, :imports], target: ActionView::RecordIdentifier.dom_id(import)
    )
  end
end
