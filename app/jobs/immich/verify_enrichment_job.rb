# frozen_string_literal: true

class Immich::VerifyEnrichmentJob < ApplicationJob
  queue_as :default

  BATCH_SIZE = 20
  MAX_PASSES = 3

  def perform(notification_id, assets, immich_url, pass: 1, confirmed: 0, unconfirmed: [])
    notification = Notification.find_by(id: notification_id)
    return unless notification

    user = notification.user
    return unless user

    if user.safe_settings.immich_url != immich_url || user.safe_settings.immich_api_key.blank?
      finish(notification, confirmed, assets.size + unconfirmed.size)
      return
    end

    saved, pending = Immich::VerifyEnrichment.new(user, assets.first(BATCH_SIZE)).call
    confirmed += saved.size
    unconfirmed += pending
    remaining = assets.drop(BATCH_SIZE)

    if remaining.any?
      self.class.perform_later(notification_id, remaining, immich_url, pass:, confirmed:, unconfirmed:)
    elsif unconfirmed.any? && pass < MAX_PASSES
      self.class.set(wait: 30.seconds).perform_later(
        notification_id, unconfirmed, immich_url, pass: pass + 1, confirmed:
      )
    else
      finish(notification, confirmed, unconfirmed.size)
    end
  end

  private

  def finish(notification, confirmed, unconfirmed)
    I18n.with_locale(notification.user.locale) do
      notification.update_with_broadcast!(
        title: I18n.t('services.immich.enrich_photos.result_title'),
        content: result_message(confirmed, unconfirmed),
        kind: unconfirmed.positive? ? :warning : :info,
        read_at: nil
      )
    end
  end

  def result_message(confirmed, unconfirmed)
    message = I18n.t('services.immich.enrich_photos.confirmed', count: confirmed)
    return message if unconfirmed.zero?

    "#{message} #{I18n.t('services.immich.enrich_photos.unconfirmed', count: unconfirmed)}"
  end
end
