# frozen_string_literal: true

module Imports::Broadcaster
  BROADCAST_INTERVAL = 5 # seconds
  BROADCAST_POINT_INTERVAL = 100 # points

  def broadcast_import_progress(import, index)
    return unless should_broadcast?(index)

    import.class.where(id: import.id)
          .where('processed < ? OR processed IS NULL', index)
          .update_all(processed: index)
    return unless reload_import(import)

    broadcast_replace_to(
      [import.user, :imports],
      target: ActionView::RecordIdentifier.dom_id(import),
      partial: 'imports/table_row',
      locals: { import: import, timezone: import.user.safe_settings.timezone }
    )

    @last_broadcast_at = Time.current
    @last_broadcast_index = index
  end

  def broadcast_status_update
    return unless reload_import(import)

    broadcast_replace_to(
      [import.user, :imports],
      target: ActionView::RecordIdentifier.dom_id(import),
      partial: 'imports/table_row',
      locals: { import: import, timezone: import.user.safe_settings.timezone }
    )
  end

  private

  # The import can be deleted while its worker is still running.
  def reload_import(import)
    import.reload
  rescue ActiveRecord::RecordNotFound
    nil
  end

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
  rescue StandardError => e
    # Broadcasts are progress UI only. In contexts without a request
    # environment (rake tasks, background jobs), rendering the partial may
    # fail (e.g. Warden::Proxy not loaded). Swallow so data ingestion
    # continues; the import is still updated via `update_column(:processed, ...)`.
    Rails.logger.warn("Imports::Broadcaster#broadcast_replace_to failed: #{e.class}: #{e.message}")
  end
end
