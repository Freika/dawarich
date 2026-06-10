# frozen_string_literal: true

class Imports::DestroyJob < ApplicationJob
  queue_as :imports

  def perform(import_id)
    import = Import.find_by(id: import_id)
    return unless import

    import.deleting!
    broadcast_status_update(import)

    Imports::Destroy.new(import.user, import).call

    broadcast_deletion_complete(import)
  rescue ActiveRecord::RecordNotFound
    Rails.logger.warn "Import #{import_id} not found, may have already been deleted"
  rescue StandardError
    revert_deleting_status(import)
    raise
  end

  private

  def revert_deleting_status(import)
    return unless import && Import.exists?(import.id)

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
  end
end
