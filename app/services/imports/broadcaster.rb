# frozen_string_literal: true

module Imports::Broadcaster
  def broadcast_import_progress(import, index)
    ImportsChannel.broadcast_to(
      import.user,
      {
        action: 'update',
        import: {
          id: import.id,
          points_count: index,
          status: import.status
        }
      }
    )
  end

  def broadcast_status_update
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
end
