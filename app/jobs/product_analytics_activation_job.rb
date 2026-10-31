# frozen_string_literal: true

class ProductAnalyticsActivationJob < ApplicationJob
  queue_as :default

  def perform(user_id, import_id: nil, source: 'other')
    user = User.find_by(id: user_id)
    return unless user&.product_analytics_consent? && !DawarichSettings.self_hosted?

    user.with_lock do
      import = Import.find_by(id: import_id, user_id: user.id) if import_id
      import_qualifies = import&.completed? && !import.demo? && import.points.exists?
      if import_qualifies && import.product_analytics_reported_at.nil?
        count = import.points.count
        captured = ProductAnalytics.capture(user: user, event: 'import_completed', channel: 'server',
                                            properties: { source: import.source || 'other',
                                                          count_bucket: count_bucket(count) },
                                            event_id: "import:#{import.id}:completed")
        import.update!(product_analytics_reported_at: Time.current) if captured
      end

      non_import_count = user.points.where(import_id: nil).limit(10).count
      if non_import_count.positive? && user.product_analytics_first_point_at.nil?
        captured = ProductAnalytics.capture(user: user, event: 'first_point_received', channel: 'server',
                                            properties: { source: source },
                                            event_id: "user:#{user.id}:first_point")
        user.update!(product_analytics_first_point_at: Time.current) if captured
      end

      if user.product_analytics_activated_at.nil? && (import_qualifies || non_import_count >= 10)
        method = import_qualifies ? 'import' : 'points'
        captured = ProductAnalytics.capture(user: user, event: 'user_activated', channel: 'server',
                                            properties: { activation_method: method },
                                            event_id: "user:#{user.id}:activated")
        user.update!(product_analytics_activated_at: Time.current) if captured
      end
    end
  end

  private

  def count_bucket(count)
    return '1' if count == 1
    return '2-9' if count < 10
    return '10-99' if count < 100
    return '100-999' if count < 1000

    '1000+'
  end
end
