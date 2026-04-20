# frozen_string_literal: true

class Api::V1::SubscriptionsController < ApiController
  skip_before_action :authenticate_api_key, only: %i[callback]
  skip_before_action :reject_pending_payment!, only: %i[callback], raise: false

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
    expected = ENV['REVENUECAT_WEBHOOK_SECRET']
    return render(json: { message: 'RevenueCat secret not configured' }, status: :service_unavailable) if expected.blank?

    provided = request.headers['Authorization'].to_s
    return render(json: { message: 'Invalid RevenueCat signature' }, status: :unauthorized) unless ActiveSupport::SecurityUtils.secure_compare(provided, expected)

    Subscription::HandleRevenueCatWebhook.new(parsed_body).call
    render json: { message: 'ok' }
  rescue Subscription::HandleRevenueCatWebhook::UnknownUser => e
    ExceptionReporter.call(e)
    render json: { message: 'Unknown user' }, status: :not_found
  end

  def handle_manager_callback
    return render(json: { message: 'Webhook secret not configured' }, status: :service_unavailable) if ENV['SUBSCRIPTION_WEBHOOK_SECRET'].blank?
    return render(json: { message: 'Invalid webhook secret' }, status: :unauthorized) unless valid_manager_secret?

    decoded_token = Subscription::DecodeJwtToken.new(params[:token]).call

    user = User.find(decoded_token[:user_id])
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

  def valid_manager_secret?
    provided = request.headers['X-Webhook-Secret'].to_s
    ActiveSupport::SecurityUtils.secure_compare(provided, ENV['SUBSCRIPTION_WEBHOOK_SECRET'].to_s)
  end
end
