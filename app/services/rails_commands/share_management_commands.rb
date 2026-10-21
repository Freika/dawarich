# frozen_string_literal: true

module RailsCommands
  module ShareManagementCommands
    HANDLERS = {
      'share_management.live_revoked' => {
        guard: 'Repeats broadcast the same revoked state to the same original share stream',
        call: lambda { |payload|
          SharedLocationChannel.broadcast_to(SharedLink.new(id: payload.fetch('share_id')), revoked: true)
        }
      }
    }.freeze
  end
end
