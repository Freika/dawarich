# frozen_string_literal: true

module WebhooksHelper
  WEBHOOK_HEALTH_BADGES = { active: 'badge-success', failing: 'badge-warning', inactive: 'badge-ghost' }.freeze

  def webhook_health_badge(webhook, scope:)
    tag.span(t("#{scope}.#{webhook.health}"), data: { testid: 'webhook-status' },
                                              class: "badge badge-sm #{WEBHOOK_HEALTH_BADGES.fetch(webhook.health)}")
  end

  def webhook_last_delivery(webhook, scope:)
    return t("#{scope}.failures", count: webhook.consecutive_failures) if webhook.consecutive_failures.positive?
    return t("#{scope}.last_success", time: time_ago_in_words(webhook.last_success_at)) if webhook.last_success_at

    t("#{scope}.never_delivered")
  end
end
