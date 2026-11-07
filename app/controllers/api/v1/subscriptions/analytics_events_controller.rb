# frozen_string_literal: true

class Api::V1::Subscriptions::AnalyticsEventsController < ApiController
  skip_before_action :authenticate_api_key, raise: false
  skip_before_action :reject_pending_payment!, raise: false

  BILLING_EVENTS = %w[trial_started paid_conversion payment_charged trial_expired
                      subscription_cancellation_scheduled payment_refunded].freeze

  def create
    return head :unauthorized unless authorized_manager?

    decoded = Subscription::DecodeJwtToken.new(params[:token], expected_purpose: 'product_analytics_billing').call
    event = decoded[:analytics_event].to_s
    unless BILLING_EVENTS.include?(event)
      return render(json: { error: 'invalid_event' },
                    status: :unprocessable_content)
    end
    return render(json: { error: 'missing_event_id' }, status: :unprocessable_content) if decoded[:event_id].blank?

    user = User.find_by(id: decoded[:user_id])
    return head :not_found unless user
    return head :no_content unless user.product_analytics_consent?

    properties = decoded[:analytics_properties] || {}
    if event == 'trial_started'
      trial_at = begin
        Time.iso8601(decoded[:occurred_at].to_s)
      rescue StandardError
        nil
      end
      properties = properties.merge(already_activated_at_trial: user.product_analytics_activated_at.present? &&
                                      trial_at.present? && user.product_analytics_activated_at <= trial_at)
    end
    captured = ProductAnalytics.capture(user: user, event: event, channel: 'billing',
                                        properties: properties,
                                        event_id: decoded[:event_id])
    captured ? head(:accepted) : head(:service_unavailable)
  rescue JWT::DecodeError
    head :unauthorized
  rescue ArgumentError
    render json: { error: 'invalid_properties' }, status: :unprocessable_content
  end

  private

  def authorized_manager?
    secret = ENV['SUBSCRIPTION_WEBHOOK_SECRET'].to_s
    secret.present? && ActiveSupport::SecurityUtils.secure_compare(request.headers['X-Webhook-Secret'].to_s, secret)
  end
end
