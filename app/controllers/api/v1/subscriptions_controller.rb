# frozen_string_literal: true

class Api::V1::SubscriptionsController < ApiController
  class PaddleSourceConflict < StandardError; end

  skip_before_action :authenticate_api_key, only: %i[callback]
  skip_before_action :reject_pending_payment!, only: %i[callback], raise: false

  BEARER_PREFIX = /\ABearer\s+/i

  def callback
    if revenuecat_event?
      handle_revenuecat_callback
    else
      handle_manager_callback
    end
  end

  private

  def revenuecat_event?
    parsed_body.is_a?(Hash) && parsed_body['event'].is_a?(Hash) && parsed_body['event']['type'].present?
  end

  def parsed_body
    @parsed_body ||= begin
      request.body.rewind
      JSON.parse(request.body.read)
    rescue JSON::ParserError
      {}
    end
  end

  def handle_revenuecat_callback
    expected = revenuecat_secret
    if expected.blank?
      return render(json: { message: 'RevenueCat secret not configured' }, status: :service_unavailable)
    end

    provided = request.headers['Authorization'].to_s.sub(BEARER_PREFIX, '')
    unless ActiveSupport::SecurityUtils.secure_compare(provided, expected)
      return render(json: { message: 'Invalid RevenueCat signature' }, status: :unauthorized)
    end

    Subscription::HandleRevenueCatWebhook.new(parsed_body).call
    render json: { message: 'ok' }
  rescue Subscription::HandleRevenueCatWebhook::UnknownUser => e
    ExceptionReporter.call(e)
    response.set_header('Retry-After', '60')
    render json: { message: 'Unknown user, retry later' }, status: :service_unavailable
  end

  def revenuecat_secret
    from_credentials =
      begin
        Rails.application.credentials.dig(:revenuecat, :webhook_secret)
      rescue StandardError
        nil
      end
    from_credentials.presence || ENV['REVENUECAT_WEBHOOK_SECRET']
  end

  def handle_manager_callback
    if ENV['SUBSCRIPTION_WEBHOOK_SECRET'].blank?
      return render(json: { message: 'Webhook secret not configured' }, status: :service_unavailable)
    end
    return render(json: { message: 'Invalid webhook secret' }, status: :unauthorized) unless valid_manager_secret?

    decoded_token = Subscription::DecodeJwtToken.new(params[:token]).call

    user = User.find(decoded_token[:user_id])

    if iap_user_with_future_entitlement?(user)
      Rails.logger.warn(
        "[Paddle callback] refusing IAP source overwrite user=#{user.id} source=#{user.subscription_source}"
      )
      return render(json: { message: 'User has active non-Paddle subscription' }, status: :conflict)
    end

    attrs = { status: decoded_token[:status], active_until: decoded_token[:active_until] }

    if decoded_token[:plan].present?
      unless User.plans.key?(decoded_token[:plan])
        return render json: { message: "Invalid plan: #{decoded_token[:plan]}" }, status: :unprocessable_content
      end

      attrs[:plan] = decoded_token[:plan]
    end

    # Manager-driven updates always imply Paddle sub source.
    attrs[:subscription_source] = :paddle

    user.update!(attrs)
    Rails.cache.delete("rack_attack/plan/#{user.api_key}") if attrs.key?(:plan)

    render json: { message: 'Subscription updated successfully' }
  rescue JWT::DecodeError => e
    ExceptionReporter.call(e)
    render json: { message: 'Failed to verify subscription update.' }, status: :unauthorized
  rescue ArgumentError => e
    ExceptionReporter.call(e)
    render json: { message: 'Invalid subscription data received.' }, status: :unprocessable_content
  end

  def iap_user_with_future_entitlement?(user)
    %w[apple_iap google_play].include?(user.subscription_source.to_s) && user.active_until&.future?
  end

  def valid_manager_secret?
    provided = request.headers['X-Webhook-Secret'].to_s
    ActiveSupport::SecurityUtils.secure_compare(provided, ENV['SUBSCRIPTION_WEBHOOK_SECRET'].to_s)
  end
end
