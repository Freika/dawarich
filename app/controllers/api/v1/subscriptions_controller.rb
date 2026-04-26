# frozen_string_literal: true

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
        ExceptionReporter.call(
          ArgumentError.new("Unknown plan in subscription callback: #{decoded[:plan].inspect}"),
          '[Subscriptions#callback] unknown plan dropped — Manager may be ahead of Dawarich'
        )
      end
    end

    attrs[:subscription_source] = decoded[:subscription_source] if decoded[:subscription_source].present?
    attrs
  end

  def stale_event?(decoded)
    return true if event_already_processed?(decoded)
    return true if event_older_than_last_seen?(decoded)

    false
  end

  def event_already_processed?(decoded)
    Rails.cache.exist?("manager_callback:processed:#{decoded[:event_id]}")
  end

  def event_older_than_last_seen?(decoded)
    ts = decoded[:event_timestamp_ms].to_i
    return false if ts.zero?

    last_seen = Rails.cache.read(last_seen_cache_key(decoded)).to_i
    ts < last_seen
  end

  def mark_event_processed(decoded)
    Rails.cache.write("manager_callback:processed:#{decoded[:event_id]}", true, expires_in: 7.days)

    ts = decoded[:event_timestamp_ms].to_i
    return if ts.zero?

    cache_key = last_seen_cache_key(decoded)
    return if ts < Rails.cache.read(cache_key).to_i

    Rails.cache.write(cache_key, ts, expires_in: 7.days)
  end

  def last_seen_cache_key(decoded)
    "manager_callback:last_seen_ms:#{decoded[:user_id]}"
  end
end
