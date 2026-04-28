# frozen_string_literal: true

class Api::V1::UsersController < ApiController
  skip_before_action :authenticate_api_key, only: %i[exist]
  skip_before_action :reject_pending_payment!, only: %i[exist], raise: false

  def me
    render json: Api::UserSerializer.new(current_api_user).call
  end

  def exist
    if ENV['SUBSCRIPTION_WEBHOOK_SECRET'].blank?
      Rails.logger.error('[Users#exist] SUBSCRIPTION_WEBHOOK_SECRET is not configured')
      return render(json: { error: 'Configuration error' }, status: :service_unavailable)
    end
    return render(json: { error: 'Invalid webhook secret' }, status: :unauthorized) unless valid_manager_secret?

    return render(json: { error: 'ids is required' }, status: :unprocessable_content) if params[:ids].nil?

    ids = Array(params[:ids]).filter_map { |raw| safe_integer(raw) }.uniq
    existing = ids.empty? ? [] : User.where(id: ids).pluck(:id)
    missing = ids - existing

    render json: { existing: existing, missing: missing }
  end

  private

  def valid_manager_secret?
    provided = request.headers['X-Webhook-Secret'].to_s
    ActiveSupport::SecurityUtils.secure_compare(provided, ENV['SUBSCRIPTION_WEBHOOK_SECRET'].to_s)
  end

  def safe_integer(raw)
    Integer(raw.to_s, 10)
  rescue ArgumentError, TypeError
    nil
  end
end
