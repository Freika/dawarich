# frozen_string_literal: true

module Imports::Broadcaster
  def broadcast_import_progress(import, index)
    ImportsChannel.broadcast_to(
      import.user,
      {
        action: 'update',
        import: {
          id: import.id,
          points_count: index
        }
      }
    )
  end
end
