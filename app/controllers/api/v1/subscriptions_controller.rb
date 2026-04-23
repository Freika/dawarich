# frozen_string_literal: true

# Single inbound endpoint for subscription state updates from the external
# subscription service. That service is the source of truth for billing;
# Dawarich only stores a read projection (plan, status, active_until,
# subscription_source) for plan gating.
#
# Contract: see superpowers/specs/2026-04-22-subscription-callback-contract.md
class Api::V1::SubscriptionsController < ApiController
  skip_before_action :authenticate_api_key, only: %i[callback]
  skip_before_action :reject_pending_payment!, only: %i[callback], raise: false

  def callback
    if ENV['SUBSCRIPTION_WEBHOOK_SECRET'].blank?
      return render(json: { message: 'Webhook secret not configured' }, status: :service_unavailable)
    end
    return render(json: { message: 'Invalid webhook secret' }, status: :unauthorized) unless valid_manager_secret?

    decoded = Subscription::DecodeJwtToken.new(params[:token]).call

    return render(json: { message: 'Missing event_id' }, status: :unprocessable_content) if decoded[:event_id].blank?

    return render(json: { message: 'Stale event' }, status: :ok) if stale_event?(decoded)

    user = User.find(decoded[:user_id])
    user.update!(subscription_attrs(decoded))

    Rails.cache.delete("rack_attack/plan/#{user.api_key}")
    mark_event_processed(decoded)

    render json: { message: 'Subscription updated successfully' }
  rescue JWT::DecodeError => e
    ExceptionReporter.call(e)
    render json: { message: 'Failed to verify subscription update.' }, status: :unauthorized
  rescue ArgumentError => e
    ExceptionReporter.call(e)
    render json: { message: 'Invalid subscription data received.' }, status: :unprocessable_content
  end

  private

  def valid_manager_secret?
    provided = request.headers['X-Webhook-Secret'].to_s
    ActiveSupport::SecurityUtils.secure_compare(provided, ENV['SUBSCRIPTION_WEBHOOK_SECRET'].to_s)
  end

  def subscription_attrs(decoded)
    attrs = { status: decoded[:status], active_until: decoded[:active_until] }

    if decoded[:plan].present?
      if User.plans.key?(decoded[:plan])
        attrs[:plan] = decoded[:plan]
      else
        Rails.logger.warn("[Subscriptions#callback] ignoring unknown plan: #{decoded[:plan].inspect}")
      end
    end

    attrs[:subscription_source] = decoded[:subscription_source] if decoded[:subscription_source].present?
    attrs
  end

  def stale_event?(decoded)
    Rails.cache.exist?("manager_callback:processed:#{decoded[:event_id]}")
  end

  def mark_event_processed(decoded)
    Rails.cache.write("manager_callback:processed:#{decoded[:event_id]}", true, expires_in: 7.days)
  end
end
