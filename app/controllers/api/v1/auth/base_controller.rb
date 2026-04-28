# frozen_string_literal: true

# Auth endpoints are accessible without an existing api_key (that's what
# sessions#create hands out) and apply to users in any status (including
# pending_payment who need to complete login to reach /trial/resume).
#
# We still want the shared middleware from ApiController — version header,
# rate-limit headers, and generic record-not-found handling — so we inherit
# from it and skip just the auth/status gates.
class Api::V1::Auth::BaseController < ApiController
  skip_before_action :authenticate_api_key, raise: false
  skip_before_action :reject_pending_payment!, raise: false

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
