# frozen_string_literal: true

module Imports::Broadcaster
  BROADCAST_INTERVAL = 5 # seconds
  BROADCAST_POINT_INTERVAL = 100 # points

  def broadcast_import_progress(import, index)
    return unless should_broadcast?(index)

    import.update_column(:processed, index) unless import.processed == index

    broadcast_replace_to(
      [import.user, :imports],
      target: ActionView::RecordIdentifier.dom_id(import),
      partial: 'imports/table_row',
      locals: { import: import }
    )

    @last_broadcast_at = Time.current
    @last_broadcast_index = index
  end

  def broadcast_status_update
    import.update_column(:processed, import.processed)

    broadcast_replace_to(
      [import.user, :imports],
      target: ActionView::RecordIdentifier.dom_id(import),
      partial: 'imports/table_row',
      locals: { import: import }
    )
  end

  private

  def should_broadcast?(index)
    return true if index.zero?

    time_elapsed = @last_broadcast_at.nil? || (Time.current - @last_broadcast_at) >= BROADCAST_INTERVAL
    points_elapsed = @last_broadcast_index.nil? || (index - @last_broadcast_index) >= BROADCAST_POINT_INTERVAL

    time_elapsed || points_elapsed
  end

  def broadcast_replace_to(stream, target:, partial:, locals:)
    Turbo::StreamsChannel.broadcast_replace_to(
      stream,
      target: target,
      partial: partial,
      locals: locals
    )
  end
end
