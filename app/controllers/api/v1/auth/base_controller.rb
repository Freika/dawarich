# frozen_string_literal: true

class Api::V1::Auth::BaseController < ActionController::API
  include ActionController::Cookies if Rails.env.test? || Rails.env.development?

  private

  def render_auth_success(user, status: :ok)
    render json: {
      user_id: user.id,
      email: user.email,
      api_key: user.api_key,
      status: user.status,
      plan: user.plan,
      subscription_source: user.subscription_source,
      active_until: user.active_until&.iso8601
    }, status: status
  end

  def render_auth_error(message, http_status: :unauthorized)
    render json: { error: 'auth_failed', message: message }, status: http_status
  end
end
