# frozen_string_literal: true

class Api::V1::Users::AnalyticsEventsController < ApiController
  skip_before_action :reject_pending_payment!, raise: false

  MOBILE_EVENTS = %w[
    mobile_first_observed cloud_signup_started cloud_signup_failed
    cloud_login_succeeded cloud_login_failed cloud_paywall_requested
    cloud_paywall_presented cloud_purchase_attempted cloud_paywall_closed
    location_permission_result background_tracking_enabled
    first_mobile_upload_confirmed
  ].freeze

  def create
    return head :forbidden if DawarichSettings.self_hosted? || !current_api_user.product_analytics_consent?

    event = params[:event].to_s
    return render(json: { error: 'invalid_event' }, status: :unprocessable_content) unless MOBILE_EVENTS.include?(event)

    properties = params[:properties].is_a?(ActionController::Parameters) ? params[:properties].to_unsafe_h : {}
    captured = ProductAnalytics.capture(user: current_api_user, event: event, channel: 'mobile',
                                        platform: params[:platform].to_s, properties: properties)
    head(captured ? :accepted : :service_unavailable)
  rescue ArgumentError
    render json: { error: 'invalid_properties' }, status: :unprocessable_content
  end
end
