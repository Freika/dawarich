# frozen_string_literal: true

class ProductAnalyticsConsent
  def self.update!(user:, consent:)
    raise ArgumentError, 'Invalid consent' unless [true, false].include?(consent)
    raise ArgumentError, 'Self-hosted analytics is disabled' if DawarichSettings.self_hosted?

    old_id = nil
    user.with_lock do
      first_consent = consent && !user.product_analytics_consent?
      non_import_count = first_consent ? user.points.where(import_id: nil).limit(10).count : 0
      previous_import = first_consent && user.imports.completed.where(demo: false).joins(:points).exists?
      old_id = user.product_analytics_id if user.product_analytics_consent? && !consent
      first_point_at = user.product_analytics_first_point_at
      first_point_at = Time.current if first_consent && non_import_count.positive?
      activated_at = user.product_analytics_activated_at
      activated_at = Time.current if first_consent && (non_import_count >= 10 || previous_import)
      user.update!(
        product_analytics_consent: consent,
        product_analytics_id: consent ? (user.product_analytics_id || SecureRandom.uuid) : nil,
        product_analytics_consented_at: consent ? (user.product_analytics_consented_at || Time.current) : nil,
        product_analytics_revoked_at: consent ? nil : Time.current,
        product_analytics_web_observed_at: consent ? user.product_analytics_web_observed_at : nil,
        product_analytics_first_point_at: consent ? first_point_at : nil,
        product_analytics_activated_at: consent ? activated_at : nil,
        utm_source: consent ? user.utm_source : nil,
        utm_medium: consent ? user.utm_medium : nil,
        utm_campaign: consent ? user.utm_campaign : nil,
        utm_term: consent ? user.utm_term : nil,
        utm_content: consent ? user.utm_content : nil
      )
    end
    ProductAnalyticsErasureJob.set(wait: 1.minute).perform_later(old_id) if old_id
    user
  end
end
