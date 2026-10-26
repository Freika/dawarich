# frozen_string_literal: true

module GeofencingHelper
  GEOFENCE_DELIVERY_DOTS = { delivered: nil, failed: 'bg-error', in_progress: 'bg-warning' }.freeze

  def geofence_delivery_status(event, webhooks:, scope:)
    deliveries = event.webhook_deliveries
    return geofence_unsent_status(event, webhooks:, scope:) if deliveries.empty?

    counts = deliveries.group_by { |delivery| geofence_delivery_state(delivery) }.transform_values(&:size)
    parts = GEOFENCE_DELIVERY_DOTS.filter_map do |state, dot_color|
      next unless counts[state]

      label = t("#{scope}.#{state}", count: counts[state])
      dot_color ? geofence_delivery_count(label, dot_color) : tag.span(label)
    end
    safe_join(parts, ', ')
  end

  private

  def geofence_unsent_status(event, webhooks:, scope:)
    return '—' if webhooks.none?
    return t("#{scope}.not_sent_late", minutes: GeofenceEvent::WEBHOOK_FRESHNESS.in_minutes.to_i) if event.skipped_late?
    return t("#{scope}.not_sent_throttled", count: GeofenceEvent::WEBHOOK_HOURLY_LIMIT) if event.skipped_throttled?

    '—'
  end

  def geofence_delivery_state(delivery)
    return :delivered if delivery.status_success?
    return :failed if delivery.status_failure?

    :in_progress if delivery.status_pending? || delivery.status_retrying?
  end

  def geofence_delivery_count(label, dot_color)
    tag.span(class: 'inline-flex items-center gap-1') do
      tag.span(class: "size-1.5 rounded-full #{dot_color}", 'aria-hidden': true) + label
    end
  end
end
