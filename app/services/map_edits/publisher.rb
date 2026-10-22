# frozen_string_literal: true

class MapEdits::Publisher
  def self.call(user:, result:)
    MapEditsChannel.broadcast_to(
      user,
      {
        type: 'point_moved',
        version: 1,
        data: MapEdits::Serializer.call(result)
      }
    )
  rescue StandardError => e
    Rails.logger.error(
      "event=map_edit.publish_failed error_class=#{e.class} point_id=#{result.point.id} track_id=#{result.track&.id}"
    )
    ActiveSupport::Notifications.instrument('point_move.post_commit_failure', operation: 'broadcast')
    record_failure_metric
    report(e)
  end

  def self.record_failure_metric
    Yabeda.dawarich_map.post_commit_failures_total.increment({ operation: 'broadcast' })
  rescue StandardError => e
    Rails.logger.warn("event=point_move.metrics_failed error_class=#{e.class}")
  end
  private_class_method :record_failure_metric

  def self.report(error)
    ExceptionReporter.call(error, 'Failed to publish committed map edit')
  rescue StandardError
    nil
  end
end
